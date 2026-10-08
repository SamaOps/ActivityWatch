import React, { useState, useEffect, useMemo } from 'react';
import axios from 'axios';
import { Activity, Search, Clock, Laptop, Calendar, Filter, Download } from 'lucide-react';
import {
  AreaChart, Area, XAxis, YAxis, CartesianGrid, Tooltip as RechartsTooltip, ResponsiveContainer,
  PieChart, Pie, Cell, Legend, BarChart, Bar
} from 'recharts';
import { format, parse, isAfter, isBefore, isEqual } from 'date-fns';

const API_URL = import.meta.env.VITE_API_URL || 'https://activitywatch-j5d5.onrender.com/api/data';
const API_KEY = import.meta.env.VITE_ACTIVE_WATCH_API_KEY || 'aw-v2-enterprise-secret-key';

const COLORS = ['#38bdf8', '#fb923c', '#10b981', '#8b5cf6', '#ef4444'];

const parseList = (text) => {
  if (!text || text === 'None') return [];
  return text.split(', ');
};

const formatDuration = (val) => {
  if (!val) return "0m";
  // If it's legacy data like "1h 30m", return as is
  if (val.includes('h') || val.includes('m')) return val;
  // Parse new integer seconds
  const seconds = parseInt(val, 10);
  if (isNaN(seconds)) return val;
  const h = Math.floor(seconds / 3600);
  const m = Math.floor((seconds % 3600) / 60);
  if (h > 0) return `${h}h ${m}m`;
  return `${m}m`;
};

const ExpandableList = ({ items, renderItem }) => {
  const [expanded, setExpanded] = useState(false);
  
  if (!items || items.length === 0) return <div style={{ color: '#64748b' }}>None</div>;
  
  if (items.length <= 2) return (
    <ul style={{ listStyle: 'none', padding: 0, margin: 0, fontSize: '0.85rem' }}>
      {items.map((item, i) => (
        <li key={i} style={{ padding: '6px 0', borderBottom: i !== items.length - 1 ? '1px solid rgba(255,255,255,0.05)' : 'none', wordBreak: 'break-all' }}>
          {renderItem ? renderItem(item) : item}
        </li>
      ))}
    </ul>
  );
  
  const displayItems = expanded ? items : items.slice(0, 2);
  return (
    <div>
      <ul style={{ listStyle: 'none', padding: 0, margin: 0, fontSize: '0.85rem' }}>
        {displayItems.map((item, i) => (
          <li key={i} style={{ padding: '6px 0', borderBottom: i !== displayItems.length - 1 ? '1px solid rgba(255,255,255,0.05)' : 'none', wordBreak: 'break-all' }}>
            {renderItem ? renderItem(item) : item}
          </li>
        ))}
      </ul>
      <button 
        onClick={() => setExpanded(!expanded)} 
        style={{ 
          background: 'rgba(56, 189, 248, 0.1)', 
          border: '1px solid rgba(56, 189, 248, 0.3)', 
          borderRadius: '4px',
          color: '#38bdf8', 
          cursor: 'pointer', 
          padding: '4px 10px', 
          marginTop: '8px',
          fontSize: '0.75rem', 
          fontWeight: 600,
          transition: 'all 0.2s'
        }}>
        {expanded ? "Show Less" : `+ ${items.length - 2} more`}
      </button>
    </div>
  );
};

function App() {
  const [data, setData] = useState([]);
  const [loading, setLoading] = useState(true);
  const [searchTerm, setSearchTerm] = useState('');
  
  // Date filters
  const [startDate, setStartDate] = useState('');
  const [endDate, setEndDate] = useState('');

  useEffect(() => {
    const fetchData = async () => {
      try {
        const response = await axios.get(API_URL, { headers: { 'X-API-KEY': API_KEY } });
        setData(response.data);
        
        // Auto-set date range based on data
        if (response.data.length > 0) {
          const dates = response.data.map(d => parse(d.date, 'MM/dd/yyyy', new Date()));
          dates.sort((a, b) => a - b);
          setStartDate(format(dates[0], 'yyyy-MM-dd'));
          setEndDate(format(dates[dates.length - 1], 'yyyy-MM-dd'));
        }
        
        setLoading(false);
      } catch (error) {
        console.error('Error fetching data:', error);
        setLoading(false);
      }
    };
    fetchData();
  }, []);

  // Time string parser (e.g. "2h 16m" -> 136 (minutes))
  const parseTimeStr = (str) => {
    if (!str || str === 'None') return 0;
    let mins = 0;
    const hMatch = str.match(/(\d+)h/);
    const mMatch = str.match(/(\d+)m/);
    if (hMatch) mins += parseInt(hMatch[1]) * 60;
    if (mMatch) mins += parseInt(mMatch[1]);
    return mins;
  };

  // Filter Data
  const filteredData = useMemo(() => {
    return data.filter(item => {
      // Text search
      const matchesSearch = 
        item.serial_no?.toLowerCase().includes(searchTerm.toLowerCase()) ||
        item.mac_address?.toLowerCase().includes(searchTerm.toLowerCase()) ||
        item.date?.includes(searchTerm);

      // Date range
      let matchesDate = true;
      
      // Filter out test records
      if (item.serial_no === 'TEST') {
        return false;
      }
      if (startDate && endDate && item.date) {
        try {
          const itemDate = parse(item.date, 'MM/dd/yyyy', new Date());
          const sDate = parse(startDate, 'yyyy-MM-dd', new Date());
          const eDate = parse(endDate, 'yyyy-MM-dd', new Date());
          matchesDate = (isAfter(itemDate, sDate) || isEqual(itemDate, sDate)) && 
                        (isBefore(itemDate, eDate) || isEqual(itemDate, eDate));
        } catch (e) {
          // ignore parsing errors
        }
      }
      return matchesSearch && matchesDate;
    });
  }, [data, searchTerm, startDate, endDate]);

  // Analytics Processing
  const { chartData, osData, dayData, stats } = useMemo(() => {
    // Group by Date for Area Chart
    const dateMap = {};
    const osCount = {};
    const seenDevices = new Set();
    const dayMap = { 'Monday': {a:0,c:0}, 'Tuesday': {a:0,c:0}, 'Wednesday': {a:0,c:0}, 'Thursday': {a:0,c:0}, 'Friday': {a:0,c:0}, 'Saturday': {a:0,c:0}, 'Sunday': {a:0,c:0} };
    
    let totalUnlocks = 0;
    let totalOffMins = 0;

    filteredData.forEach(item => {
      const activeMins = parseTimeStr(item.total_active_time);
      const afkMins = parseTimeStr(item.afk_time);
      const offMins = parseTimeStr(item.off_time);
      
      totalUnlocks += parseInt(item.times_opened) || 0;
      totalOffMins += offMins;
      
      if (item.day_of_week && dayMap[item.day_of_week]) {
         dayMap[item.day_of_week].a += activeMins;
         dayMap[item.day_of_week].c += 1;
      }

      if (!dateMap[item.date]) {
        dateMap[item.date] = { name: item.date, active: 0, afk: 0, off: 0, count: 0 };
      }
      dateMap[item.date].active += activeMins;
      dateMap[item.date].afk += afkMins;
      dateMap[item.date].off += offMins;
      dateMap[item.date].count += 1;

      if (!seenDevices.has(item.serial_no)) {
        seenDevices.add(item.serial_no);
        osCount[item.os] = (osCount[item.os] || 0) + 1;
      }
    });

    const cData = Object.values(dateMap).map(d => ({
      name: d.name,
      'Active Time (mins)': Math.round(d.active / d.count), // Average per device
      'AFK Time (mins)': Math.round(d.afk / d.count)
    })).sort((a, b) => new Date(a.name) - new Date(b.name));

    const oData = Object.keys(osCount).map(os => ({
      name: os,
      value: osCount[os]
    }));

    const dData = Object.keys(dayMap).map(d => ({
      name: d.substring(0,3),
      'Avg Active Mins': dayMap[d].c > 0 ? Math.round(dayMap[d].a / dayMap[d].c) : 0
    }));
    
    const stats = {
      avgUnlocks: filteredData.length > 0 ? Math.round(totalUnlocks / filteredData.length) : 0,
      avgOffTimeMins: filteredData.length > 0 ? Math.round(totalOffMins / filteredData.length) : 0
    };

    return { chartData: cData, osData: oData, dayData: dData, stats };
  }, [filteredData]);

  if (loading) {
    return (
      <div className="loading-state">
        <div className="spinner"></div>
        <h2 style={{ fontWeight: '500', color: '#94a3b8', marginTop: '1.5rem', letterSpacing: '0.05em' }}>Loading Telemetry Data...</h2>
      </div>
    );
  }

  return (
    <div className="dashboard-container">
      <header className="header">
        <h1 className="title">
          <Activity size={36} color="#38bdf8" />
          ActivityWatch
        </h1>
        <div className="header-controls">
          <div className="date-filter">
            <span className="filter-label">Start Date:</span>
            <input type="date" value={startDate} onChange={(e) => setStartDate(e.target.value)} className="date-input" />
          </div>
          <div className="date-filter">
            <span className="filter-label">End Date:</span>
            <input type="date" value={endDate} onChange={(e) => setEndDate(e.target.value)} className="date-input" />
          </div>
          <button className="btn-export"><Download size={16}/> Export CSV</button>
        </div>
      </header>

      <div className="stats-grid">
        <div className="stat-card">
          <div className="stat-title">Total Logs matching criteria</div>
          <div className="stat-value">{filteredData.length}</div>
        </div>
        <div className="stat-card">
          <div className="stat-title">Unique Devices</div>
          <div className="stat-value">
            {new Set(filteredData.map(d => d.serial_no)).size}
          </div>
        </div>
        <div className="stat-card">
          <div className="stat-title">Avg Active Time</div>
          <div className="stat-value" style={{ color: 'var(--success)' }}>
            {filteredData.length > 0 ? 
              `${Math.floor(filteredData.reduce((acc, curr) => acc + parseTimeStr(curr.total_active_time), 0) / filteredData.length / 60)}h ${Math.floor(filteredData.reduce((acc, curr) => acc + parseTimeStr(curr.total_active_time), 0) / filteredData.length % 60)}m` 
              : '0h 0m'}
          </div>
        </div>
        <div className="stat-card">
          <div className="stat-title">Avg AFK Time</div>
          <div className="stat-value" style={{ color: '#fb923c' }}>
          {filteredData.length > 0 ? 
              `${Math.floor(filteredData.reduce((acc, curr) => acc + parseTimeStr(curr.afk_time), 0) / filteredData.length / 60)}h ${Math.floor(filteredData.reduce((acc, curr) => acc + parseTimeStr(curr.afk_time), 0) / filteredData.length % 60)}m` 
              : '0h 0m'}
          </div>
        </div>
        <div className="stat-card">
          <div className="stat-title">Avg Off Time</div>
          <div className="stat-value" style={{ color: '#94a3b8' }}>
            {`${Math.floor(stats.avgOffTimeMins / 60)}h ${stats.avgOffTimeMins % 60}m`}
          </div>
        </div>
        <div className="stat-card">
          <div className="stat-title">Avg Daily Unlocks</div>
          <div className="stat-value" style={{ color: '#38bdf8' }}>
            {stats.avgUnlocks}
          </div>
        </div>
      </div>

      <div className="charts-grid">
        <div className="chart-card chart-large">
          <h3 className="chart-title">Activity Trend Over Time (Avg Minutes per Device)</h3>
          <ResponsiveContainer width="100%" height={300}>
            <AreaChart data={chartData} margin={{ top: 10, right: 30, left: 0, bottom: 0 }}>
              <defs>
                <linearGradient id="colorActive" x1="0" y1="0" x2="0" y2="1">
                  <stop offset="5%" stopColor="#10b981" stopOpacity={0.4}/>
                  <stop offset="95%" stopColor="#10b981" stopOpacity={0}/>
                </linearGradient>
                <linearGradient id="colorAFK" x1="0" y1="0" x2="0" y2="1">
                  <stop offset="5%" stopColor="#fb923c" stopOpacity={0.4}/>
                  <stop offset="95%" stopColor="#fb923c" stopOpacity={0}/>
                </linearGradient>
              </defs>
              <XAxis dataKey="name" stroke="#94a3b8" fontSize={12} tickLine={false} />
              <YAxis stroke="#94a3b8" fontSize={12} tickLine={false} axisLine={false} />
              <CartesianGrid strokeDasharray="3 3" stroke="rgba(255,255,255,0.05)" vertical={false} />
              <RechartsTooltip 
                contentStyle={{ backgroundColor: '#1e293b', border: '1px solid rgba(255,255,255,0.1)', borderRadius: '8px', color: '#fff' }}
                itemStyle={{ color: '#fff' }}
              />
              <Legend verticalAlign="top" height={36}/>
              <Area type="monotone" dataKey="Active Time (mins)" stroke="#10b981" strokeWidth={3} fillOpacity={1} fill="url(#colorActive)" />
              <Area type="monotone" dataKey="AFK Time (mins)" stroke="#fb923c" strokeWidth={3} fillOpacity={1} fill="url(#colorAFK)" />
            </AreaChart>
          </ResponsiveContainer>
        </div>
        
        <div className="chart-card chart-small">
          <h3 className="chart-title">Operating System Distribution</h3>
          <ResponsiveContainer width="100%" height={300}>
            <PieChart>
              <Pie
                data={osData}
                cx="50%"
                cy="50%"
                innerRadius={60}
                outerRadius={100}
                paddingAngle={5}
                dataKey="value"
                stroke="none"
              >
                {osData.map((entry, index) => (
                  <Cell key={`cell-${index}`} fill={COLORS[index % COLORS.length]} />
                ))}
              </Pie>
              <RechartsTooltip contentStyle={{ backgroundColor: '#1e293b', border: '1px solid rgba(255,255,255,0.1)', borderRadius: '8px', color: '#fff' }} />
              <Legend />
            </PieChart>
          </ResponsiveContainer>
        </div>
        
        <div className="chart-card chart-large" style={{ marginTop: '1rem' }}>
          <h3 className="chart-title">Activity by Day of Week (Avg Active Mins)</h3>
          <ResponsiveContainer width="100%" height={250}>
            <BarChart data={dayData} margin={{ top: 10, right: 30, left: 0, bottom: 0 }}>
              <CartesianGrid strokeDasharray="3 3" stroke="rgba(255,255,255,0.05)" vertical={false} />
              <XAxis dataKey="name" stroke="#94a3b8" fontSize={12} tickLine={false} />
              <YAxis stroke="#94a3b8" fontSize={12} tickLine={false} axisLine={false} />
              <RechartsTooltip 
                contentStyle={{ backgroundColor: '#1e293b', border: '1px solid rgba(255,255,255,0.1)', borderRadius: '8px', color: '#fff' }}
                cursor={{ fill: 'rgba(255,255,255,0.05)' }}
              />
              <Bar dataKey="Avg Active Mins" fill="#8b5cf6" radius={[4, 4, 0, 0]} />
            </BarChart>
          </ResponsiveContainer>
        </div>
      </div>

      <div className="data-table-container">
        <div className="table-header">
          <h2 style={{ fontSize: '1.5rem', fontWeight: 600 }}>Detailed Telemetry Logs</h2>
          <div style={{ position: 'relative' }}>
            <Search size={18} style={{ position: 'absolute', left: '12px', top: '50%', transform: 'translateY(-50%)', color: 'var(--text-muted)' }} />
            <input 
              type="text" 
              className="search-input" 
              style={{ paddingLeft: '2.5rem' }}
              placeholder="Search Serial, MAC, Date..." 
              value={searchTerm}
              onChange={(e) => setSearchTerm(e.target.value)}
            />
          </div>
        </div>

        <div className="table-wrapper">
          <table>
            <thead>
              <tr>
                <th>Date</th>
                <th>Day</th>
                <th>Device (Serial / MAC)</th>
                <th>OS</th>
                <th>First Active</th>
                <th>Last Active</th>
                <th>Active Time</th>
                <th>AFK Time</th>
                <th>Off Time</th>
                <th>Times Opened</th>
                <th>Top Apps</th>
                <th>Top Websites</th>
                <th>Last Sync</th>
                <th>Location</th>
                <th>Version</th>
              </tr>
            </thead>
            <tbody>
              {filteredData.map((row, index) => {
                const apps = parseList(row.top_apps);
                const websites = parseList(row.top_websites);
                
                return (
                  <tr key={index}>
                    <td style={{ fontWeight: 500, whiteSpace: 'nowrap' }}>{row.date}</td>
                    <td>{row.day_of_week}</td>
                    <td>
                      <div style={{ fontWeight: '600' }}>{row.serial_no.split(' | ')[0]}</div>
                      <div style={{ fontSize: '0.8rem', color: 'var(--text-muted)' }}>{row.mac_address}</div>
                    </td>
                    <td>
                      <span className={`badge os-${row.os}`}>{row.os}</span>
                    </td>
                    <td style={{ whiteSpace: 'nowrap' }}>{row.first_active}</td>
                    <td style={{ whiteSpace: 'nowrap' }}>{row.last_active}</td>
                    <td style={{ color: 'var(--success)', fontWeight: 600, whiteSpace: 'nowrap' }}>{formatDuration(row.total_active_time)}</td>
                    <td style={{ color: '#fb923c', whiteSpace: 'nowrap' }}>{formatDuration(row.afk_time)}</td>
                    <td style={{ color: '#94a3b8', whiteSpace: 'nowrap' }}>{formatDuration(row.off_time)}</td>
                    <td style={{ textAlign: 'center' }}>{row.times_opened}</td>
                    <td style={{ verticalAlign: 'top', minWidth: '220px' }}>
                      <ExpandableList items={apps} />
                    </td>
                    <td style={{ verticalAlign: 'top', minWidth: '300px' }}>
                      <ExpandableList 
                        items={websites} 
                        renderItem={(site) => (
                          site.startsWith('http') ? (
                            <a href={site.split(' ')[0]} target="_blank" rel="noopener noreferrer" style={{ color: '#38bdf8', textDecoration: 'none' }}>
                              {site}
                            </a>
                          ) : (
                            site
                          )
                        )}
                      />
                    </td>
                    <td style={{ whiteSpace: 'nowrap', color: '#8b5cf6', fontSize: '0.9rem' }}>{row.last_sync_time || 'N/A'}</td>
                    <td style={{ minWidth: '150px' }}>{row.location || 'Unknown Location'}</td>
                    <td style={{ whiteSpace: 'nowrap' }}>
                      <span style={{
                        background: 'rgba(56,189,248,0.1)',
                        border: '1px solid rgba(56,189,248,0.3)',
                        borderRadius: '4px',
                        color: '#38bdf8',
                        padding: '2px 8px',
                        fontSize: '0.8rem',
                        fontWeight: 600
                      }}>
                        {row.tracker_version || 'Unknown'}
                      </span>
                    </td>
                  </tr>
                );
              })}
              {filteredData.length === 0 && (
                <tr>
                  <td colSpan="15" style={{ textAlign: 'center', padding: '4rem', color: 'var(--text-muted)' }}>
                    No telemetry data found matching criteria.
                  </td>
                </tr>
              )}
            </tbody>
          </table>
        </div>
      </div>
    </div>
  );
}

export default App;
