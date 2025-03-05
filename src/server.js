// Load environment variables
import dotenv from 'dotenv';
import http from 'http';
import { getAppInfo } from './index.js';

dotenv.config({ path: './config/.env.deploy' });

const HOST = process.env.HOST || '0.0.0.0';
const PORT = process.env.PORT || 3000;

// ------------------------------------------




const server = http.createServer((req, res) => {
  const appInfo = getAppInfo();
  
  // Set response headers
  res.setHeader('Content-Type', 'application/json');
  res.statusCode = 200;
  
  // Get deployment information
  const responseData = {
    message: 'CD Pipeline Test Application is running!',
    timestamp: new Date().toISOString(),
    ...appInfo,
    endpoint: req.url,
    environment: {
      node: process.version,
      ...Object.fromEntries(
        Object.entries(process.env)
          .filter(([key]) => key.startsWith('APP_') || key === 'PORT' || key === 'HOST')
          .map(([key, value]) => [key, value])
      )
    }
  };
  
  res.end(JSON.stringify(responseData, null, 2));
});



// ------------------------------------------

// Start server
server.listen(PORT, HOST, () => {
  console.log(`Server running at http://${HOST}:${PORT}/`);
  console.log(`Environment: ${process.env.APP_ENV || 'development'}`);
  console.log(`Deployment ID: ${process.env.APP_DEPLOYMENT || 'local'}`);
});

// Handle graceful shutdown
process.on('SIGTERM', () => {
  console.log('SIGTERM signal received: closing HTTP server');
  server.close(() => {
    console.log('HTTP server closed');
    process.exit(0);
  });
});
