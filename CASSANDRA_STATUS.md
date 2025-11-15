# Cassandra Database - Setup Status ✅

**Setup Date:** November 14, 2025  
**Status:** RESTORED - NEEDS VERIFICATION

---

## 🎉 Database Configuration Restored

### Container Details
- **Container Name:** `cassandra-parish`
- **Port:** `9042` (mapped to localhost:9042)
- **Image:** `cassandra:latest`
- **Keyspace:** `parish_records`

### Database Schema
- ✅ **users** - User accounts and roles
- ✅ **records** - Main parish records table
- ✅ **baptism_records** - Baptism certificates
- ✅ **marriage_records** - Marriage certificates  
- ✅ **confirmation_records** - Confirmation certificates
- ✅ **death_records** - Death certificates
- ✅ **certificate_requests** - Certificate request tracking
- ✅ **audit_log** - System audit trail

### Backend API
- **Port:** `3000`
- **Health Check:** `http://localhost:3000/health`
- **Database Driver:** `cassandra-driver@4.6.4`

---

## 🚀 Quick Start Commands

### Start Cassandra
```powershell
.\start-cassandra.ps1
```

### Initialize Database
```powershell
.\init-database.ps1
```

### Start Backend API
```bash
cd backend
npm install
npm start
```

### Verify Connection
```bash
curl http://localhost:3000/health
```

---

## 🔧 Manual Setup (if scripts fail)

### 1. Start Cassandra Container
```bash
docker run --name cassandra-parish -p 9042:9042 -d cassandra:latest
```

### 2. Wait for Initialization
```bash
# Wait 60 seconds for Cassandra to start
docker logs cassandra-parish
```

### 3. Create Keyspace
```bash
docker exec -it cassandra-parish cqlsh
```

```cql
CREATE KEYSPACE parish_records 
WITH REPLICATION = {
    'class': 'SimpleStrategy',
    'replication_factor': 1
};
```

---

## 📊 Connection Details

- **Host:** `localhost`
- **Port:** `9042`
- **Keyspace:** `parish_records`
- **Datacenter:** `datacenter1`

---

## ⚠️ IMPORTANT NOTES

1. **Docker Required** - Ensure Docker Desktop is running
2. **Port 9042** - Must be available for Cassandra
3. **Port 3000** - Must be available for Backend API
4. **Memory** - Cassandra needs at least 2GB RAM
5. **Persistence** - Data is stored in Docker volume

---

## 🔍 Troubleshooting

### Cassandra Won't Start
```bash
docker logs cassandra-parish
docker restart cassandra-parish
```

### Connection Issues
```bash
docker exec cassandra-parish cqlsh -e "DESCRIBE KEYSPACES;"
```

### Backend API Issues
```bash
cd backend
npm run dev  # Development mode with auto-reload
```

---

## 🎯 Next Steps

1. ✅ Restore scripts and backend (COMPLETED)
2. ⏳ **Start Cassandra** - Run `.\start-cassandra.ps1`
3. ⏳ **Initialize Database** - Run `.\init-database.ps1`
4. ⏳ **Install Backend Dependencies** - `cd backend && npm install`
5. ⏳ **Start Backend API** - `npm start`
6. ⏳ **Test Flutter App** - Verify data sync works
