const cassandra = require('cassandra-driver');

class CassandraClient {
  constructor() {
    this.client = null;
    this.keyspace = 'parish_records';
  }

  async connect() {
    try {
      this.client = new cassandra.Client({
        contactPoints: [process.env.CASSANDRA_HOST || 'localhost'],
        localDataCenter: process.env.CASSANDRA_DATACENTER || 'datacenter1',
        keyspace: this.keyspace,
        authProvider: process.env.CASSANDRA_USERNAME ? 
          new cassandra.auth.PlainTextAuthProvider(
            process.env.CASSANDRA_USERNAME, 
            process.env.CASSANDRA_PASSWORD
          ) : null
      });

      await this.client.connect();
      console.log('✅ Connected to Cassandra cluster');
      
      // Test the connection
      const result = await this.client.execute('SELECT now() FROM system.local');
      console.log('📅 Database time:', result.rows[0]['system.now()']);
      
    } catch (error) {
      console.error('❌ Failed to connect to Cassandra:', error);
      throw error;
    }
  }

  async execute(query, params = []) {
    if (!this.client) {
      throw new Error('Database not connected');
    }
    
    try {
      const result = await this.client.execute(query, params, { prepare: true });
      return result;
    } catch (error) {
      console.error('Database query error:', error);
      throw error;
    }
  }

  async executeWithOptions(query, params = [], options = {}) {
    if (!this.client) {
      throw new Error('Database not connected');
    }
    
    try {
      const result = await this.client.execute(query, params, { prepare: true, ...options });
      return result;
    } catch (error) {
      console.error('Database query error:', error);
      throw error;
    }
  }

  getState() {
    if (!this.client) {
      return 'disconnected';
    }

    const state = this.client.getState();

    // cassandra-driver state object exposes connected hosts; if there is at least
    // one connected host we treat the database as connected.
    const connectedHosts = state.getConnectedHosts
      ? state.getConnectedHosts()
      : state.connectedHosts;

    return connectedHosts && connectedHosts.length > 0
      ? 'connected'
      : 'disconnected';
  }

  async shutdown() {
    if (this.client) {
      await this.client.shutdown();
      console.log('🔌 Disconnected from Cassandra');
    }
  }

  // Helper methods for common operations
  async insertRecord(table, data) {
    const columns = Object.keys(data).join(', ');
    const placeholders = Object.keys(data).map(() => '?').join(', ');
    const values = Object.values(data);
    
    const query = `INSERT INTO ${table} (${columns}) VALUES (${placeholders})`;
    return await this.execute(query, values);
  }

  async updateRecord(table, data, whereClause, whereParams) {
    const setClause = Object.keys(data).map(key => `${key} = ?`).join(', ');
    const values = [...Object.values(data), ...whereParams];
    
    const query = `UPDATE ${table} SET ${setClause} WHERE ${whereClause}`;
    return await this.execute(query, values);
  }

  async selectRecords(table, whereClause = '', params = [], limit = null) {
    let query = `SELECT * FROM ${table}`;
    if (whereClause) {
      query += ` WHERE ${whereClause}`;
    }
    if (limit) {
      query += ` LIMIT ${limit}`;
    }
    
    return await this.execute(query, params);
  }

  async deleteRecord(table, whereClause, params) {
    const query = `DELETE FROM ${table} WHERE ${whereClause}`;
    return await this.execute(query, params);
  }
}

module.exports = new CassandraClient();
