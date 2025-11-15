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
    
    // Check if we already have data
    const existingRecords = await cassandraClient.execute(
      'SELECT COUNT(*) as count FROM records'
    );
    
    if (existingRecords.rows[0].count > 0) {
      console.log('📋 Sample data already exists, skipping...');
      return;
    }

    // Insert sample records
    const sampleRecords = [
      {
        id: 'uuid()',
        type: 'baptism',
        name: 'John Michael Smith',
        date: '2024-01-15',
        place: 'Holy Rosary Church',
        parish: 'Holy Rosary Parish',
        notes: JSON.stringify({
          parents: 'Robert Smith and Maria Smith',
          godparents: 'James Wilson and Sarah Wilson',
          minister: 'Fr. Antonio Cruz'
        }),
        certificate_status: 'approved',
        created_at: 'toTimestamp(now())',
        updated_at: 'toTimestamp(now())',
        registry_number: '2024-001-B'
      },
      {
        id: 'uuid()',
        type: 'marriage',
        name: 'David Johnson and Lisa Brown',
        date: '2024-02-20',
        place: 'Holy Rosary Church',
        parish: 'Holy Rosary Parish',
        notes: JSON.stringify({
          witnesses: 'Mark Johnson and Jennifer Brown',
          minister: 'Fr. Antonio Cruz'
        }),
        certificate_status: 'pending',
        created_at: 'toTimestamp(now())',
        updated_at: 'toTimestamp(now())',
        registry_number: '2024-001-M'
      },
      {
        id: 'uuid()',
        type: 'confirmation',
        name: 'Emily Rose Garcia',
        date: '2024-03-10',
        place: 'Holy Rosary Church',
        parish: 'Holy Rosary Parish',
        notes: JSON.stringify({
          sponsor: 'Maria Santos',
          minister: 'Bishop Carlos Rodriguez'
        }),
        certificate_status: 'approved',
        created_at: 'toTimestamp(now())',
        updated_at: 'toTimestamp(now())',
        registry_number: '2024-001-C'
      }
    ];

    for (const record of sampleRecords) {
      const columns = Object.keys(record).join(', ');
      const values = Object.values(record).map(v => 
        typeof v === 'string' && (v.includes('uuid()') || v.includes('toTimestamp')) ? v : `'${v}'`
      ).join(', ');
      
      const query = `INSERT INTO records (${columns}) VALUES (${values})`;
      
      try {
        await cassandraClient.execute(query);
        console.log(`✅ Inserted sample record: ${record.name}`);
      } catch (error) {
        console.error(`❌ Failed to insert sample record: ${record.name}`, error);
      }
    }

    // Insert sample user (admin)
    const adminUser = {
      id: 'uuid()',
      email: 'admin@holyrosary.com',
      display_name: 'System Administrator',
      role: 'admin',
      created_at: 'toTimestamp(now())',
      last_login: 'toTimestamp(now())',
      email_verified: true,
      status: 'active'
    };

    const userColumns = Object.keys(adminUser).join(', ');
    const userValues = Object.values(adminUser).map(v => 
      typeof v === 'string' && (v.includes('uuid()') || v.includes('toTimestamp')) ? v : `'${v}'`
    ).join(', ');
    
    const userQuery = `INSERT INTO users (${userColumns}) VALUES (${userValues})`;
    
    try {
      await cassandraClient.execute(userQuery);
      console.log('✅ Inserted admin user');
    } catch (error) {
      console.error('❌ Failed to insert admin user:', error);
    }

    console.log('📊 Sample data insertion completed');
  }

  async verifyDatabase() {
    console.log('🔍 Verifying database setup...');
    
    try {
      // Test basic queries
      const recordCount = await cassandraClient.execute('SELECT COUNT(*) as count FROM records');
      const userCount = await cassandraClient.execute('SELECT COUNT(*) as count FROM users');
      
      console.log(`📋 Records in database: ${recordCount.rows[0].count}`);
      console.log(`👥 Users in database: ${userCount.rows[0].count}`);
      
      // Test indexes
      const recentRecords = await cassandraClient.execute(
        'SELECT * FROM records_by_type WHERE type = ? LIMIT 5',
        ['baptism']
      );
      
      console.log(`🔍 Index test successful: Found ${recentRecords.rows.length} baptism records`);
      
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
