const express = require('express');
const cassandraClient = require('../database/cassandra');

const router = express.Router();

// Get all users (admin only)
router.get('/', async (req, res) => {
  try {
    const result = await cassandraClient.execute(
      'SELECT id, email, display_name, role, created_at, last_login, email_verified FROM users LIMIT 100'
    );
    
    res.json({
      users: result.rows,
      count: result.rows.length
    });

  } catch (error) {
    console.error('Get users error:', error);
    res.status(500).json({ error: 'Failed to fetch users' });
  }
});

// Get user by ID
router.get('/:id', async (req, res) => {
  try {
    const { id } = req.params;
    
    const result = await cassandraClient.execute(
      'SELECT id, email, display_name, role, created_at, last_login, email_verified FROM users WHERE id = ?',
      [id]
    );
    
    if (result.rows.length === 0) {
      return res.status(404).json({ error: 'User not found' });
    }
    
    res.json(result.rows[0]);

  } catch (error) {
    console.error('Get user error:', error);
    res.status(500).json({ error: 'Failed to fetch user' });
  }
});

// Update user role (admin only)
router.put('/:id/role', async (req, res) => {
  try {
    const { id } = req.params;
    const { role } = req.body;

    if (!['admin', 'staff', 'volunteer'].includes(role)) {
      return res.status(400).json({ error: 'Invalid role' });
    }

    await cassandraClient.execute(
      'UPDATE users SET role = ? WHERE id = ?',
      [role, id]
    );

    res.json({ message: 'User role updated successfully' });

  } catch (error) {
    console.error('Update user role error:', error);
    res.status(500).json({ error: 'Failed to update user role' });
  }
});

// Update user profile
router.put('/:id', async (req, res) => {
  try {
    const { id } = req.params;
    const { displayName, emailVerified } = req.body;

    await cassandraClient.execute(
      'UPDATE users SET display_name = ?, email_verified = ? WHERE id = ?',
      [displayName, emailVerified, id]
    );

    res.json({ message: 'User profile updated successfully' });

  } catch (error) {
    console.error('Update user profile error:', error);
    res.status(500).json({ error: 'Failed to update user profile' });
  }
});

// Delete user (admin only)
router.delete('/:id', async (req, res) => {
  try {
    const { id } = req.params;

    await cassandraClient.execute(
      'DELETE FROM users WHERE id = ?',
      [id]
    );

    res.json({ message: 'User deleted successfully' });

  } catch (error) {
    console.error('Delete user error:', error);
    res.status(500).json({ error: 'Failed to delete user' });
  }
});

// Get user statistics
router.get('/stats/overview', async (req, res) => {
  try {
    // Get total users
    const totalResult = await cassandraClient.execute('SELECT COUNT(*) as count FROM users');
    const totalUsers = totalResult.rows[0].count;

    // Get users by role
    const adminResult = await cassandraClient.execute(
      'SELECT COUNT(*) as count FROM users WHERE role = ? ALLOW FILTERING',
      ['admin']
    );
    const staffResult = await cassandraClient.execute(
      'SELECT COUNT(*) as count FROM users WHERE role = ? ALLOW FILTERING',
      ['staff']
    );

    res.json({
      totalUsers: totalUsers.toNumber(),
      adminUsers: adminResult.rows[0].count.toNumber(),
      staffUsers: staffResult.rows[0].count.toNumber(),
      timestamp: new Date().toISOString()
    });

  } catch (error) {
    console.error('Get user stats error:', error);
    res.status(500).json({ error: 'Failed to fetch user statistics' });
  }
});

module.exports = router;
