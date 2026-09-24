import React, { useState, useEffect } from 'react';
import axios from 'axios';
import { Activity, Search, Clock, Laptop, Calendar } from 'lucide-react';

const API_URL = import.meta.env.VITE_API_URL || 'https://activitywatch-j5d5.onrender.com/api/data';

function App() {
  const [data, setData] = useState([]);
  const [loading, setLoading] = useState(true);
  const [searchTerm, setSearchTerm] = useState('');

  useEffect(() => {
    const fetchData = async () => {
      try {
        const response = await axios.get(API_URL);
        setData(response.data);
        setLoading(false);
      } catch (error) {
        console.error('Error fetching data:', error);
        setLoading(false);
      }
    };
    fetchData();
  }, []);

  const filteredData = data.filter(item => 
    item.serial_no?.toLowerCase().includes(searchTerm.toLowerCase()) ||
    item.mac_address?.toLowerCase().includes(searchTerm.toLowerCase()) ||
    item.date?.includes(searchTerm)
  );

  if (loading) {
    return (
      <div className="loading-state">
        <div className="spinner"></div>
        <h2>Syncing ActivityWatch Data...</h2>
      </div>
    );
  }

  return (
    <div className="dashboard-container">
      <header className="header">
        <h1 className="title">
          <Activity size={36} color="#38bdf8" />
          ActivityWatch Orbit
        </h1>
      </header>

      <div className="stats-grid">
        <div className="stat-card">
          <div className="stat-title">Total Devices Tracked</div>
          <div className="stat-value">
            {new Set(data.map(d => d.serial_no)).size}
          </div>
        </div>
        <div className="stat-card">
          <div className="stat-title">Latest Sync Date</div>
          <div className="stat-value">
            {data.length > 0 ? data[0].date : 'N/A'}
          </div>
        </div>
        <div className="stat-card">
          <div className="stat-title">Total Logs</div>
          <div className="stat-value">{data.length}</div>
        </div>
      </div>

      <div className="data-table-container">
        <div className="table-header">
          <h2 style={{ fontSize: '1.5rem', fontWeight: 600 }}>Student Activity Logs</h2>
          <div style={{ position: 'relative' }}>
            <Search size={18} style={{ position: 'absolute', left: '12px', top: '50%', transform: 'translateY(-50%)', color: 'var(--text-muted)' }} />
            <input 
              type="text" 
              className="search-input" 
              style={{ paddingLeft: '2.5rem' }}
              placeholder="Search by Serial, MAC, or Date..." 
              value={searchTerm}
              onChange={(e) => setSearchTerm(e.target.value)}
            />
          </div>
        </div>

        <div style={{ overflowX: 'auto' }}>
          <table>
            <thead>
              <tr>
                <th><Calendar size={14} style={{ display: 'inline', marginRight: '4px' }}/> Date</th>
                <th><Laptop size={14} style={{ display: 'inline', marginRight: '4px' }}/> Device (Serial / MAC)</th>
                <th>OS</th>
                <th><Clock size={14} style={{ display: 'inline', marginRight: '4px' }}/> Total Active</th>
                <th>AFK Time</th>
                <th>Top Apps</th>
                <th>Top Websites</th>
              </tr>
            </thead>
            <tbody>
              {filteredData.map((row, index) => (
                <tr key={index}>
                  <td style={{ fontWeight: 500 }}>{row.date}</td>
                  <td>
                    <div>{row.serial_no}</div>
                    <div style={{ fontSize: '0.8rem', color: 'var(--text-muted)' }}>{row.mac_address}</div>
                  </td>
                  <td>
                    <span className={`badge os-${row.os}`}>{row.os}</span>
                  </td>
                  <td style={{ color: 'var(--success)', fontWeight: 600 }}>{row.total_active_time}</td>
                  <td style={{ color: '#fb923c' }}>{row.afk_time}</td>
                  <td>
                    <div className="truncate" title={row.top_apps}>{row.top_apps}</div>
                  </td>
                  <td>
                    <div className="truncate" title={row.top_websites}>{row.top_websites}</div>
                  </td>
                </tr>
              ))}
              {filteredData.length === 0 && (
                <tr>
                  <td colSpan="7" style={{ textAlign: 'center', padding: '3rem', color: 'var(--text-muted)' }}>
                    No tracking data found matching "{searchTerm}"
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
