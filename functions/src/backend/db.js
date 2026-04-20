module.exports = {
  async connect() {
    return;
  },

  async shutdown() {
    return;
  },

  getState() {
    return 'disabled';
  },

  async execute() {
    throw new Error('Database disabled');
  },

  async executeWithOptions() {
    throw new Error('Database disabled');
  },
};
