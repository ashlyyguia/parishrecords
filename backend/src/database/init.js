const fs = require('fs');
const path = require('path');
const cassandraClient = require('./cassandra');

class DatabaseInitializer {
  constructor() {
    this.schemaPath = path.join(__dirname, 'schema.cql');
  }

  async initializeDatabase() {
    try {
      console.log('🔧 Initializing Parish Records database...');
      
      // Connect to Cassandra (without keyspace first)
      await this.connectWithoutKeyspace();
      
      // Read and execute schema
      await this.executeSchema();
      
      // Reconnect with keyspace
      await cassandraClient.connect();
      
      // Insert sample data if needed
      await this.insertSampleData();
      
      console.log('✅ Database initialization completed successfully!');
      
    } catch (error) {
      console.error('❌ Database initialization failed:', error);
      throw error;
    }
  }

  async connectWithoutKeyspace() {
    const cassandra = require('cassandra-driver');
    
    this.tempClient = new cassandra.Client({
      contactPoints: [process.env.CASSANDRA_HOST || 'localhost'],
      localDataCenter: process.env.CASSANDRA_DATACENTER || 'datacenter1',
      authProvider: process.env.CASSANDRA_USERNAME ? 
        new cassandra.auth.PlainTextAuthProvider(
          process.env.CASSANDRA_USERNAME, 
          process.env.CASSANDRA_PASSWORD
        ) : null
    });

    await this.tempClient.connect();
    console.log('📡 Connected to Cassandra cluster (no keyspace)');
  }

  async executeSchema() {
    console.log('📋 Executing database schema...');
    
    const schemaContent = fs.readFileSync(this.schemaPath, 'utf8');
    
    // Split schema into individual statements
    const statements = schemaContent
      .split(';')
      .map(stmt => stmt.trim())
      .filter(stmt => stmt.length > 0 && !stmt.startsWith('--'));

    for (const statement of statements) {
      if (statement.trim()) {
        try {
          await this.tempClient.execute(statement);
          console.log(`✅ Executed: ${statement.substring(0, 50)}...`);
        } catch (error) {
          if (!error.message.includes('already exists')) {
            console.error(`❌ Failed to execute: ${statement.substring(0, 50)}...`);
            throw error;
          }
        }
      }
    }

    await this.tempClient.shutdown();
  }

  async insertSampleData() {
    console.log('📊 Inserting sample data...');
    
    // For the revised schema we do not insert default sample data here
    console.log('📋 Sample data insertion skipped for revised schema.');
  }

  async verifyDatabase() {
    console.log('🔍 Verifying database setup...');
    
    try {
      // Test basic queries against notifications table
      const notificationCount = await cassandraClient.execute('SELECT COUNT(*) as count FROM notifications');
      
      console.log(`🔔 Notifications in database: ${notificationCount.rows[0].count}`);
      
      console.log('✅ Database verification completed successfully!');
      
    } catch (error) {
      console.error('❌ Database verification failed:', error);
      throw error;
    }
  }
}

// CLI usage
if (require.main === module) {
  const initializer = new DatabaseInitializer();
  
  initializer.initializeDatabase()
    .then(() => initializer.verifyDatabase())
    .then(() => {
      console.log('🎉 Database setup completed successfully!');
      process.exit(0);
    })
    .catch((error) => {
      console.error('💥 Database setup failed:', error);
      process.exit(1);
    });
}

module.exports = DatabaseInitializer;
