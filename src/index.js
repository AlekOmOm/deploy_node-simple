// Simple module to demonstrate functionality
const getAppInfo = () => {
  return {
    name: process.env.APP_NAME || 'test-cd-app',
    version: process.env.APP_VERSION || '1.0.0',
    environment: process.env.APP_ENV || 'development',
    deploymentId: process.env.APP_DEPLOYMENT || 'local',
  };
};

export default getAppInfo;
