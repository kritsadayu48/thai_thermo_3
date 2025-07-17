const express = require('express');
const admin = require('firebase-admin');
const axios = require('axios');
const cron = require('node-cron');

const app = express();
app.use(express.json());

// เริ่มต้น Firebase Admin SDK
const serviceAccount = require('./earthquake-5b60b-firebase-adminsdk-fbsvc-08df3f2140.json');
admin.initializeApp({
  credential: admin.credential.cert(serviceAccount)
});

// การตั้งค่าเริ่มต้นสำหรับเซิร์ฟเวอร์
const globalSettings = {
  enabled: true,
  filterByMagnitude: true,
  minMagnitude: 3.5,
  filterByRegion: true,
  defaultRegion: 'all', // sea (เอเชียตะวันออกเฉียงใต้), th (ประเทศไทย), all, cn (จีน), jp (ญี่ปุ่น), ph (ฟิลิปปินส์), id (อินโดนีเซีย), mm (พม่า)
  checkIntervalMinutes: 1,
  autoCheckOnStartup: true,
  notificationTimeout: 12 * 60 * 60 * 1000, // 12 hours
  logFilteringDetails: true,
  // เพิ่มการตั้งค่าสำหรับการกรองตามระยะทาง
  filterByDistance: false,
  maxDistanceKm: 2000,
  userLatitude: null,
  userLongitude: null
};

// ตัวแปรการตั้งค่า - ค่าเริ่มต้นสำหรับอุปกรณ์ใหม่
const defaultSettings = { ...globalSettings };

// เก็บการตั้งค่าแยกตามอุปกรณ์
const deviceSettings = {};

// เพิ่มแมปเก็บความสัมพันธ์ระหว่าง token กับ device ID
const tokenToDeviceMap = new Map();

// ฐานข้อมูลอย่างง่ายสำหรับเก็บ tokens
const tokens = new Set();
// เก็บ ID ของแผ่นดินไหวที่เคยส่งแจ้งเตือนไปแล้ว
const notifiedEarthquakes = new Set();
// เปลี่ยนเป็นแบบ Map เพื่อเก็บข้อมูลแยกตาม deviceId
const deviceNotifiedEarthquakes = new Map(); // deviceId -> Set of earthquake IDs

// เพิ่มตัวแปรเก็บข้อมูลว่า token ไหนได้รับแจ้งเตือนไปแล้วบ้าง
const tokenNotifications = new Map(); // token -> Set of earthquake IDs

// ตรวจสอบว่ามี req.body หรือไม่
app.use((req, res, next) => {
  if (req.method === 'POST' && !req.body) {
    console.log('Missing request body, headers:', req.headers);
  }
  next();
});

// Helper function เพื่อดึงการตั้งค่าของอุปกรณ์
function getDeviceSettings(deviceId) {
  // ถ้าไม่มี deviceId ให้ใช้ค่าเริ่มต้น
  if (!deviceId) {
    console.log('Warning: No device ID provided, using default settings');
    return { ...defaultSettings };
  }
  
  // ถ้าอุปกรณ์นี้ไม่เคยมีการตั้งค่ามาก่อน ให้ใช้ค่าเริ่มต้น
  if (!deviceSettings[deviceId]) {
    deviceSettings[deviceId] = { ...defaultSettings, deviceId };
    console.log(`Created default settings for device: ${deviceId}`);
  }
  
  return deviceSettings[deviceId];
}

// API สำหรับลงทะเบียน token
app.post('/register-token', (req, res) => {
  try {
    const { token, deviceId } = req.body;
    if (!token) {
      return res.status(400).send({ success: false, error: 'Token is required' });
    }
    
    // ถ้ามี deviceId มาด้วย ให้สร้างความสัมพันธ์ระหว่าง token กับ deviceId
    if (deviceId) {
      console.log(`Registering token for device: ${deviceId}`);
      
      // สร้างการตั้งค่าเริ่มต้นสำหรับอุปกรณ์ใหม่
      if (!deviceSettings[deviceId]) {
        deviceSettings[deviceId] = { ...defaultSettings, deviceId };
        console.log(`Created default settings for device: ${deviceId}`);
      }
      
      // ผูก token กับ deviceId
      tokenToDeviceMap.set(token, deviceId);
      console.log(`Token ${token.substring(0, 8)}... mapped to device ${deviceId}`);
    } else {
      console.log('Warning: Device ID not provided during token registration');
    }
    
    tokens.add(token);
    console.log(`Token registered: ${token}`);
    
    // ส่งกลับข้อมูลการตั้งค่าปัจจุบันให้กับอุปกรณ์
    const settings = deviceId ? deviceSettings[deviceId] : defaultSettings;
    
    res.status(200).send({ 
      success: true, 
      settings,
      message: deviceId 
        ? `Token registered and mapped to device ${deviceId}` 
        : 'Token registered without device ID'
    });
  } catch (error) {
    console.error('Error in register-token:', error);
    res.status(500).send({ success: false, error: error.message });
  }
});

// เพิ่ม: API สำหรับการลงทะเบียนโดยตรง (สำหรับ fallback)
app.post('/register-token-direct', (req, res) => {
  try {
    const { token, deviceId, platform, timestamp } = req.body;
    
    if (!token || !deviceId) {
      return res.status(400).send({ 
        success: false, 
        error: 'Both token and deviceId are required' 
      });
    }
    
    console.log(`Direct token registration for device: ${deviceId}`);
    
    // สร้างหรืออัปเดตการตั้งค่า
    if (!deviceSettings[deviceId]) {
      deviceSettings[deviceId] = { ...defaultSettings, deviceId };
      console.log(`Created default settings for device: ${deviceId}`);
    }
    
    // ลบการผูกเดิมของ token นี้ (ถ้ามี)
    for (const [existingToken, existingDeviceId] of tokenToDeviceMap.entries()) {
      if (existingToken === token && existingDeviceId !== deviceId) {
        console.log(`Removing previous mapping of token ${token.substring(0, 8)}... from device ${existingDeviceId}`);
        tokenToDeviceMap.delete(existingToken);
      }
    }
    
    // สร้างการผูกใหม่
    tokenToDeviceMap.set(token, deviceId);
    tokens.add(token);
    
    console.log(`Direct token registration: ${token.substring(0, 8)}... mapped to device ${deviceId}`);
    
    res.status(200).send({
      success: true,
      message: `Token directly registered for device ${deviceId}`,
      settings: deviceSettings[deviceId]
    });
  } catch (error) {
    console.error('Error in register-token-direct:', error);
    res.status(500).send({ success: false, error: error.message });
  }
});

// เพิ่ม: API สำหรับการลงทะเบียนทางเลือก (สำหรับกรณีลงทะเบียนปกติไม่สำเร็จ)
app.post('/register-token-alternative', (req, res) => {
  try {
    const { token, deviceId, platform, forceUpdate, timestamp } = req.body;
    
    if (!token) {
      return res.status(400).send({ success: false, error: 'Token is required' });
    }
    
    // สำหรับการลงทะเบียนทางเลือก จำเป็นต้องมี deviceId
    if (!deviceId) {
      return res.status(400).send({ 
        success: false, 
        error: 'Device ID is required for alternative registration' 
      });
    }
    
    console.log(`Alternative token registration for device: ${deviceId}`);
    
    // สร้างหรืออัปเดตการตั้งค่า
    if (!deviceSettings[deviceId]) {
      deviceSettings[deviceId] = { ...defaultSettings, deviceId };
      console.log(`Created default settings for device: ${deviceId}`);
    }
    
    // หากเป็นการบังคับอัปเดต ให้ลบการผูกเดิมทั้งหมด
    if (forceUpdate) {
      // ลบการผูกเดิมของ token นี้ (ถ้ามี)
      const tokensToUpdate = [];
      for (const [existingToken, existingDeviceId] of tokenToDeviceMap.entries()) {
        if (existingDeviceId === deviceId) {
          tokensToUpdate.push(existingToken);
        }
      }
      
      // ลบการผูกเดิมของอุปกรณ์นี้
      tokensToUpdate.forEach(existingToken => {
        console.log(`Removing previous mapping of device ${deviceId} with token ${existingToken.substring(0, 8)}...`);
        tokenToDeviceMap.delete(existingToken);
      });
    }
    
    // สร้างการผูกใหม่
    tokenToDeviceMap.set(token, deviceId);
    tokens.add(token);
    
    console.log(`Alternative token registration: ${token.substring(0, 8)}... mapped to device ${deviceId}`);
    
    res.status(200).send({
      success: true,
      message: `Token registered via alternative method for device ${deviceId}`,
      settings: deviceSettings[deviceId]
    });
  } catch (error) {
    console.error('Error in register-token-alternative:', error);
    res.status(500).send({ success: false, error: error.message });
  }
});

// ใหม่: API สำหรับตั้งค่าภูมิภาคที่ต้องการกรอง
app.post('/set-region', (req, res) => {
  try {
    const { region, deviceId } = req.body;
    
    if (!region) {
      return res.status(400).json({ error: 'Region parameter is required' });
    }
    
    // ตรวจสอบความถูกต้องของค่าภูมิภาค
    const validRegions = ['all', 'sea', 'th', 'cn', 'jp', 'ph', 'id', 'mm'];
    if (!validRegions.includes(region)) {
      return res.status(400).json({ 
        error: 'Invalid region value',
        validRegions
      });
    }
    
    if (deviceId) {
      // ตั้งค่าสำหรับอุปกรณ์เฉพาะ
      const settings = getDeviceSettings(deviceId);
      settings.defaultRegion = region;
      console.log(`Device ${deviceId}: Set region to "${region}"`);
      
      res.status(200).json({
        message: `Region set to "${region}" for device ${deviceId}`,
        settings
      });
    } else {
      // ตั้งค่าสำหรับทั้งระบบ (global setting)
      globalSettings.defaultRegion = region;
      console.log(`Global setting: Set region to "${region}"`);
      
      res.status(200).json({
        message: `Global region set to "${region}"`,
        settings: globalSettings
      });
    }
  } catch (error) {
    console.error('Error setting region:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// ใหม่: API สำหรับตั้งค่าขนาดแผ่นดินไหวขั้นต่ำ
app.post('/set-min-magnitude', (req, res) => {
  const { magnitude, deviceId } = req.body;
  
  if (!magnitude) {
    return res.status(400).json({ error: 'Magnitude is required' });
  }
  
  if (!deviceId) {
    return res.status(400).json({ error: 'Device ID is required' });
  }

  if (!deviceSettings[deviceId]) {
    deviceSettings[deviceId] = { ...defaultSettings };
  }
  
  deviceSettings[deviceId].minMagnitude = parseFloat(magnitude);
  console.log(`Set minimum magnitude for device ${deviceId} to ${magnitude}`);
  
  return res.json({ success: true, minMagnitude: deviceSettings[deviceId].minMagnitude });
});

// ใหม่: API สำหรับตั้งค่าตำแหน่งและระยะทางการกรอง
app.post('/set-location-filter', (req, res) => {
  const { latitude, longitude, maxDistanceKm, enabled, deviceId } = req.body;
  
  if (!deviceId) {
    return res.status(400).json({ error: 'Device ID is required' });
  }

  if (!deviceSettings[deviceId]) {
    deviceSettings[deviceId] = { ...defaultSettings };
  }
  
  // อัปเดตการตั้งค่า
  if (latitude !== undefined) {
    deviceSettings[deviceId].userLatitude = parseFloat(latitude);
  }
  
  if (longitude !== undefined) {
    deviceSettings[deviceId].userLongitude = parseFloat(longitude);
  }
  
  if (maxDistanceKm !== undefined) {
    deviceSettings[deviceId].maxDistanceKm = parseFloat(maxDistanceKm);
  }
  
  if (enabled !== undefined) {
    deviceSettings[deviceId].filterByDistance = Boolean(enabled);
  }
  
  console.log(`Updated location filter for device ${deviceId}:`, {
    latitude: deviceSettings[deviceId].userLatitude,
    longitude: deviceSettings[deviceId].userLongitude,
    maxDistanceKm: deviceSettings[deviceId].maxDistanceKm,
    enabled: deviceSettings[deviceId].filterByDistance
  });
  
  return res.json({ 
    success: true, 
    settings: {
      userLatitude: deviceSettings[deviceId].userLatitude,
      userLongitude: deviceSettings[deviceId].userLongitude,
      maxDistanceKm: deviceSettings[deviceId].maxDistanceKm,
      filterByDistance: deviceSettings[deviceId].filterByDistance
    }
  });
});

// ใหม่: API สำหรับดูการตั้งค่าปัจจุบัน
app.get('/get-settings', (req, res) => {
  const { deviceId } = req.query;
  
  if (!deviceId) {
    return res.status(400).json({ error: 'Device ID is required' });
  }
  
  const settings = getDeviceSettings(deviceId);
  
  return res.json({ 
    success: true, 
    settings: settings
  });
});

// ใหม่: API สำหรับเปิด/ปิดการกรองตามภูมิภาค
app.post('/toggle-region-filter', (req, res) => {
  try {
    const { enabled, deviceId } = req.body;
    
    if (enabled === undefined) {
      return res.status(400).json({ error: 'Enabled parameter is required' });
    }
    
    if (deviceId) {
      // ตั้งค่าสำหรับอุปกรณ์เฉพาะ
      const settings = getDeviceSettings(deviceId);
      settings.filterByRegion = !!enabled;
      console.log(`Device ${deviceId}: Region filtering ${settings.filterByRegion ? 'enabled' : 'disabled'}`);
      
      res.status(200).json({
        message: `Region filtering ${settings.filterByRegion ? 'enabled' : 'disabled'} for device ${deviceId}`,
        settings
      });
    } else {
      // ตั้งค่าสำหรับทั้งระบบ (global setting)
      globalSettings.filterByRegion = !!enabled;
      console.log(`Global setting: Region filtering ${globalSettings.filterByRegion ? 'enabled' : 'disabled'}`);
      
      res.status(200).json({
        message: `Global region filtering ${globalSettings.filterByRegion ? 'enabled' : 'disabled'}`,
        settings: globalSettings
      });
    }
  } catch (error) {
    console.error('Error toggling region filter:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// ใหม่: API สำหรับเปิด/ปิดการกรองตามขนาดแผ่นดินไหว
app.post('/toggle-magnitude-filter', (req, res) => {
  try {
    const { enabled, deviceId } = req.body;
    if (enabled === undefined) {
      return res.status(400).json({ success: false, error: 'Enabled flag is required' });
    }
    
    if (!deviceId) {
      return res.status(400).json({ success: false, error: 'Device ID is required' });
    }
    
    // ดึงการตั้งค่าของอุปกรณ์นี้
    const settings = getDeviceSettings(deviceId);
    
    settings.filterByMagnitude = Boolean(enabled);
    console.log(`Device ${deviceId}: Magnitude filtering ${settings.filterByMagnitude ? 'enabled' : 'disabled'}`);
    
    res.status(200).json({ 
      success: true, 
      message: `Magnitude filtering ${settings.filterByMagnitude ? 'enabled' : 'disabled'}`,
      settings: {
        filterByMagnitude: settings.filterByMagnitude,
        minMagnitude: settings.minMagnitude
      }
    });
  } catch (error) {
    console.error('Error in toggle-magnitude-filter:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// API สำหรับส่งการแจ้งเตือนทดสอบ
app.post('/test-notification', async (req, res) => {
  try {
    const { token, title, body, deviceId, 
            magnitude, location, latitude, longitude, depth } = req.body;
    
    if (!token) {
      return res.status(400).json({ success: false, error: 'Token is required' });
    }
    
    // กำหนดค่าเริ่มต้นสำหรับข้อมูลที่ไม่ได้ระบุ
    const testMagnitude = magnitude || '5.0';
    const testLocation = location || 'ทดสอบ, ประเทศไทย';
    const testLatitude = latitude || '13.7563';
    const testLongitude = longitude || '100.5018';
    const testDepth = depth || '10.0';
    const testId = 'test_' + Date.now();
    
    console.log(`สร้างข้อมูลทดสอบ: ID=${testId}, Magnitude=${testMagnitude}, Location=${testLocation}`);
    
    const message = {
      token: token,
      notification: {
        title: title || 'ทดสอบการแจ้งเตือน',
        body: body || `ทดสอบขนาด ${testMagnitude} ที่ ${testLocation}`
      },
      data: {
        id: testId,
        magnitude: testMagnitude,
        place: testLocation,
        time: new Date().toISOString(),
        notification_time: new Date().toISOString(), // เพิ่มเวลาที่ส่งแจ้งเตือน
        latitude: testLatitude,
        longitude: testLongitude,
        depth: testDepth,
        location: testLocation,
        isTest: 'true'
      },
      android: {
        priority: "high",
        notification: {
          channel_id: "earthquake_alerts",
          tag: "earthquake_notification",
          clickAction: "FLUTTER_NOTIFICATION_CLICK",
          sound: "default",
          icon: "@mipmap/ic_launcher"
        }
      },
      apns: {
        headers: {
          "apns-priority": "10"
        },
        payload: {
          aps: {
            alert: {
              title: title || 'ทดสอบการแจ้งเตือน',
              body: body || `ทดสอบขนาด ${testMagnitude} ที่ ${testLocation}`
            },
            badge: 1,
            sound: "default",
            "content-available": 1
          }
        }
      }
    };
    
    try {
      // ลอกข้อมูลสำคัญก่อนส่ง
      console.log(`ส่งข้อมูลทดสอบ: ID=${testId}, Magnitude=${testMagnitude}, Location=${testLocation}, Token=${token.substring(0, 6)}...`);
      
      await admin.messaging().send(message);
      
      console.log(`Test notification sent to token: ${token.substring(0, 6)}...`);
      res.status(200).json({ 
        success: true, 
        details: {
          id: testId,
          magnitude: testMagnitude,
          location: testLocation
        }
      });
    } catch (error) {
      console.error('Error sending test notification:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  } catch (error) {
    console.error('Error in test-notification:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// ใหม่: API สำหรับดูการตั้งค่าปัจจุบัน
app.get('/settings', (req, res) => {
  try {
    const deviceId = req.query.deviceId;
    
    if (!deviceId) {
      return res.status(400).json({ success: false, error: 'Device ID is required as a query parameter' });
    }
    
    // ดึงการตั้งค่าของอุปกรณ์นี้
    const settings = getDeviceSettings(deviceId);
    
    res.status(200).json({ 
      success: true, 
      settings: {
        enabled: settings.enabled,
        checkIntervalMinutes: settings.checkIntervalMinutes,
        filterByRegion: settings.filterByRegion,
        defaultRegion: settings.defaultRegion,
        filterByMagnitude: settings.filterByMagnitude,
        minMagnitude: settings.minMagnitude,
        autoCheckOnStartup: settings.autoCheckOnStartup,
        logFilteringDetails: settings.logFilteringDetails
      }
    });
  } catch (error) {
    console.error('Error in get settings:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// API สำหรับทดสอบการดึงข้อมูลแผ่นดินไหว
app.get('/check-earthquakes', async (req, res) => {
  try {
    console.log('Manually checking for new earthquakes...');
    const deviceId = req.query.deviceId;
    
    if (!deviceId) {
      return res.status(400).json({ success: false, error: 'Device ID is required as a query parameter' });
    }
    
    // ดึงการตั้งค่าของอุปกรณ์นี้
    const settings = getDeviceSettings(deviceId);
    
    const earthquakes = await fetchEarthquakes();
    
    // กรองแผ่นดินไหวตามภูมิภาคและขนาดก่อนส่งกลับ
    let filteredEarthquakes = earthquakes;
    let filteredOut = [];
    
    if (settings.filterByRegion || settings.filterByMagnitude || settings.filterByDistance) {
      console.log(`Filtering earthquakes for device ${deviceId}:`);
      
      if (settings.filterByRegion) {
        console.log(`- By region: "${settings.defaultRegion}"`);
      }
      
      if (settings.filterByMagnitude) {
        console.log(`- By magnitude: >= ${settings.minMagnitude}`);
      }
      
      if (settings.filterByDistance) {
        console.log(`- By distance: <= ${settings.maxDistanceKm}km from (${settings.userLatitude}, ${settings.userLongitude})`);
      }
      
      filteredEarthquakes = earthquakes.filter(quake => {
        const place = quake.properties.place || "";
        const magnitude = quake.properties.mag || 0;
        const earthquakeLat = quake.geometry.coordinates[1];
        const earthquakeLon = quake.geometry.coordinates[0];
        let shouldInclude = true;
        const filterReason = {};
        
        // ตรวจสอบตามภูมิภาค
        if (settings.filterByRegion && settings.defaultRegion !== 'all') {
          const matchesRegion = shouldNotifyBasedOnRegion(place, settings.defaultRegion, settings);
          if (!matchesRegion) {
            shouldInclude = false;
            filterReason.region = true;
          }
        }
        
        // ตรวจสอบตามขนาด
        if (settings.filterByMagnitude) {
          if (magnitude < settings.minMagnitude) {
            shouldInclude = false;
            filterReason.magnitude = true;
          }
        }
        
        // ตรวจสอบตามระยะทาง
        if (settings.filterByDistance) {
          if (!isWithinDistance(earthquakeLat, earthquakeLon, settings.userLatitude, settings.userLongitude, settings.maxDistanceKm)) {
            shouldInclude = false;
            filterReason.distance = true;
          }
        }
        
        // บันทึกแผ่นดินไหวที่ถูกกรองออก
        if (!shouldInclude) {
          const distance = settings.userLatitude && settings.userLongitude ? 
            calculateDistance(settings.userLatitude, settings.userLongitude, earthquakeLat, earthquakeLon) : null;
          
          filteredOut.push({
            id: quake.id,
            magnitude: magnitude,
            place: place,
            distance: distance ? distance.toFixed(1) : null,
            reason: filterReason
          });
        }
        
        return shouldInclude;
      });
      
      console.log(`Device ${deviceId}: Filtered from ${earthquakes.length} to ${filteredEarthquakes.length} earthquakes`);
      
      // แสดงรายละเอียดผลการกรอง
      const filteredByRegion = filteredOut.filter(q => q.reason.region).length;
      const filteredByMagnitude = filteredOut.filter(q => q.reason.magnitude).length;
      const filteredByDistance = filteredOut.filter(q => q.reason.distance).length;
      
      console.log(`Filtering details for device ${deviceId}:`);
      console.log(`- By region: ${filteredByRegion} earthquakes`);
      console.log(`- By magnitude: ${filteredByMagnitude} earthquakes`);
      console.log(`- By distance: ${filteredByDistance} earthquakes`);
    }
    
    // เรียก sendNotifications พร้อมข้อมูลอุปกรณ์
    const notificationResults = await sendNotifications(earthquakes, deviceId);
    
    res.status(200).json({ 
      success: true,
      settings: {
        filterByRegion: settings.filterByRegion,
        defaultRegion: settings.defaultRegion,
        filterByMagnitude: settings.filterByMagnitude,
        minMagnitude: settings.minMagnitude,
        filterByDistance: settings.filterByDistance,
        maxDistanceKm: settings.maxDistanceKm,
        userLatitude: settings.userLatitude,
        userLongitude: settings.userLongitude
      },
      total: earthquakes.length,
      filtered: {
        count: earthquakes.length - filteredEarthquakes.length,
        byRegion: filteredOut.filter(q => q.reason.region).length,
        byMagnitude: filteredOut.filter(q => q.reason.magnitude).length,
        byDistance: filteredOut.filter(q => q.reason.distance).length,
        earthquakes: filteredOut
      },
      earthquakes: filteredEarthquakes,
      notificationsCount: notificationResults.count,
      notifiedQuakes: notificationResults.quakes,
      filteredByNotification: notificationResults.filtered || 0
    });
  } catch (error) {
    console.error('Error in check-earthquakes:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// API สำหรับทดสอบ cron job
app.get('/test-cron', (req, res) => {
  try {
    console.log('Testing cron job execution...');
    // เริ่มต้น cron job ใหม่
    if (cronJob) {
      cronJob.stop();
    }
    
    console.log(`Re-creating cron job with interval: ${globalSettings.checkIntervalMinutes} minutes`);
    cronJob = cron.schedule(`*/${globalSettings.checkIntervalMinutes} * * * *`, () => {
      console.log(`Cron job triggered at ${new Date().toISOString()}`);
      checkEarthquakesAndNotify();
    });
    
    // ทดสอบเรียกใช้ทันที
    checkEarthquakesAndNotify();
    
    res.status(200).json({ 
      success: true, 
      message: `Cron job restarted with interval: ${globalSettings.checkIntervalMinutes} minutes and executed immediately` 
    });
  } catch (error) {
    console.error('Error in test-cron:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// API สำหรับดูรายการ tokens ทั้งหมด
app.get('/tokens', (req, res) => {
  try {
    const tokenList = Array.from(tokens);
    res.status(200).json({ 
      success: true, 
      count: tokenList.length, 
      tokens: tokenList 
    });
  } catch (error) {
    console.error('Error in tokens:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// เพิ่มช่องทางรีเซ็ตรายการแผ่นดินไหวที่แจ้งเตือนแล้ว
app.post('/reset-notifications', (req, res) => {
  try {
    notifiedEarthquakes.clear();
    deviceNotifiedEarthquakes.clear();
    console.log('Cleared all notified earthquakes history');
    res.status(200).json({ success: true, message: 'Notification history cleared' });
  } catch (error) {
    console.error('Error in reset-notifications:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// API สำหรับลบ token ที่ไม่ใช้แล้ว
app.delete('/token/:token', (req, res) => {
  try {
    const tokenToRemove = req.params.token;
    if (tokens.has(tokenToRemove)) {
      tokens.delete(tokenToRemove);
      console.log(`Token removed: ${tokenToRemove}`);
      res.status(200).json({ success: true });
    } else {
      res.status(404).json({ success: false, error: 'Token not found' });
    }
  } catch (error) {
    console.error('Error in delete token:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// เพิ่ม: API สำหรับล้างประวัติการแจ้งเตือนตามอุปกรณ์
app.post('/reset-device-notifications', (req, res) => {
  try {
    const { deviceId } = req.body;
    
    if (!deviceId) {
      // ถ้าไม่มี deviceId มา ไม่สามารถล้างเฉพาะอุปกรณ์ได้
      return res.status(400).send({ 
        success: false, 
        error: 'Device ID is required to reset notifications for a specific device' 
      });
    }
    
    console.log(`Resetting notification history for device: ${deviceId}`);
    
    // หา tokens ที่เกี่ยวข้องกับอุปกรณ์นี้
    const deviceTokens = [];
    for (const [token, mappedDeviceId] of tokenToDeviceMap.entries()) {
      if (mappedDeviceId === deviceId) {
        deviceTokens.push(token);
      }
    }
    
    // ล้างประวัติการแจ้งเตือนสำหรับ tokens ที่เกี่ยวข้อง
    let clearedCount = 0;
    deviceTokens.forEach(token => {
      if (tokenNotifications.has(token)) {
        tokenNotifications.delete(token);
        clearedCount++;
      }
    });
    
    // ล้างประวัติการแจ้งเตือนของอุปกรณ์นี้
    if (deviceNotifiedEarthquakes.has(deviceId)) {
      deviceNotifiedEarthquakes.delete(deviceId);
      console.log(`Cleared device-specific earthquake notification history for ${deviceId}`);
    }
    
    console.log(`Cleared notification history for ${clearedCount} tokens associated with device: ${deviceId}`);
    
    res.status(200).send({
      success: true,
      message: `Cleared notification history for device: ${deviceId} (${clearedCount} tokens affected)`,
      clearedTokens: clearedCount
    });
  } catch (error) {
    console.error('Error in reset-device-notifications:', error);
    res.status(500).send({ success: false, error: error.message });
  }
});

// ฟังก์ชันดึงข้อมูลแผ่นดินไหวจาก USGS
async function fetchEarthquakes() {
  try {
    // ดึงแผ่นดินไหวที่เกิดขึ้นใน 30 นาทีล่าสุด
    const endTime = new Date();
    const startTime = new Date(endTime.getTime() - 30 * 60 * 1000);
    
    const response = await axios.get('https://earthquake.usgs.gov/fdsnws/event/1/query', {
      params: {
        format: 'geojson',
        starttime: startTime.toISOString(),
        endtime: endTime.toISOString(),
        minmagnitude: 0.1 // ใช้ค่าต่ำเพื่อดึงทุกเหตุการณ์
      }
    });
    
    console.log(`Fetched ${response.data.features.length} earthquakes from USGS API`);
    return response.data.features;
  } catch (error) {
    console.error('Error fetching earthquakes:', error);
    return [];
  }
}

// เพิ่มฟังก์ชันสำหรับตรวจสอบตำแหน่งของแผ่นดินไหว
// ฟังก์ชันเหล่านี้ต้องตรงกับที่ใช้ในแอปพลิเคชัน

// ตรวจสอบว่าตำแหน่งอยู่ในประเทศไทยหรือไม่
function isInThailand(location) {
  return location.toLowerCase().includes('thailand') || 
         location.toLowerCase().includes('ประเทศไทย') || 
         location.toLowerCase().includes('ไทย');
}

// ตรวจสอบว่าตำแหน่งอยู่ในเอเชียตะวันออกเฉียงใต้หรือไม่
function isInSoutheastAsia(location) {
  const seaCountries = ['thailand', 'malaysia', 'singapore', 'indonesia', 'philippines', 
                        'vietnam', 'cambodia', 'laos', 'myanmar', 'brunei', 'east timor',
                        'ประเทศไทย', 'ไทย', 'มาเลเซีย', 'สิงคโปร์', 'อินโดนีเซีย', 
                        'ฟิลิปปินส์', 'เวียดนาม', 'กัมพูชา', 'ลาว', 'พม่า', 'บรูไน'];
  
  const locationLower = location.toLowerCase();
  return seaCountries.some(country => locationLower.includes(country)) ||
         locationLower.includes('southeast asia') ||
         locationLower.includes('เอเชียตะวันออกเฉียงใต้');
}

// ตรวจสอบว่าตำแหน่งอยู่ในจีนหรือไม่
function isInChina(location) {
  return location.toLowerCase().includes('china') || 
         location.toLowerCase().includes('จีน');
}

// ตรวจสอบว่าตำแหน่งอยู่ในญี่ปุ่นหรือไม่
function isInJapan(location) {
  return location.toLowerCase().includes('japan') || 
         location.toLowerCase().includes('ญี่ปุ่น');
}

// ตรวจสอบว่าตำแหน่งอยู่ในฟิลิปปินส์หรือไม่
function isInPhilippines(location) {
  return location.toLowerCase().includes('philippines') || 
         location.toLowerCase().includes('ฟิลิปปินส์');
}

// ตรวจสอบว่าตำแหน่งอยู่ในอินโดนีเซียหรือไม่
function isInIndonesia(location) {
  return location.toLowerCase().includes('indonesia') || 
         location.toLowerCase().includes('อินโดนีเซีย');
}

// ตรวจสอบว่าตำแหน่งอยู่ในพม่าหรือไม่
function isInMyanmar(location) {
  return location.toLowerCase().includes('myanmar') || 
         location.toLowerCase().includes('burma') || 
         location.toLowerCase().includes('พม่า');
}

// ฟังก์ชันคำนวณระยะทางระหว่างพิกัดสองจุดโดยใช้ Haversine formula
function calculateDistance(lat1, lon1, lat2, lon2) {
  const R = 6371; // รัศมีของโลกในหน่วยกิโลเมตร
  const dLat = (lat2 - lat1) * Math.PI / 180;
  const dLon = (lon2 - lon1) * Math.PI / 180;
  const a = 
    Math.sin(dLat/2) * Math.sin(dLat/2) +
    Math.cos(lat1 * Math.PI / 180) * Math.cos(lat2 * Math.PI / 180) * 
    Math.sin(dLon/2) * Math.sin(dLon/2);
  const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1-a));
  const distance = R * c; // ระยะทางในหน่วยกิโลเมตร
  return distance;
}

// ตรวจสอบว่าแผ่นดินไหวอยู่ในระยะที่กำหนดหรือไม่
function isWithinDistance(earthquakeLat, earthquakeLon, userLat, userLon, maxDistanceKm) {
  if (!userLat || !userLon || !earthquakeLat || !earthquakeLon) {
    return true; // ถ้าไม่มีข้อมูลตำแหน่ง ให้ผ่านการกรอง
  }
  
  const distance = calculateDistance(userLat, userLon, earthquakeLat, earthquakeLon);
  return distance <= maxDistanceKm;
}

// ตรวจสอบว่าควรส่งการแจ้งเตือนแผ่นดินไหวนี้หรือไม่ตามภูมิภาคที่กำหนด
function shouldNotifyBasedOnRegion(place, regionCode, deviceSettings) {
  // ถ้าไม่มีการกรองตามภูมิภาค หรือเลือก "ทั้งหมด" ให้ส่งแจ้งเตือนทุกรายการ
  if (!deviceSettings.filterByRegion || regionCode === 'all') {
    return true;
  }

  // ตรวจสอบตามภูมิภาคที่เลือก
  switch (regionCode) {
    case 'th':
      return isInThailand(place);
    case 'sea':
      return isInSoutheastAsia(place);
    case 'cn':
      return isInChina(place);
    case 'jp':
      return isInJapan(place);
    case 'ph':
      return isInPhilippines(place);
    case 'id':
      return isInIndonesia(place);
    case 'mm':
      return isInMyanmar(place);
    default:
      return true; // ถ้าไม่รู้จักรหัสภูมิภาค ให้ส่งแจ้งเตือนทั้งหมด
  }
}

// ฟังก์ชันส่งการแจ้งเตือน
async function sendNotifications(earthquakes, deviceId = null) {
  console.log(`Called sendNotifications with ${earthquakes.length} earthquakes, ${tokens.size} tokens, device: ${deviceId || 'unknown'}`);
  
  // ดึงการตั้งค่าของอุปกรณ์ที่ระบุ (หรือใช้ค่าเริ่มต้นถ้าไม่ระบุ)
  const globalSettings = { ...defaultSettings };
  
  // แสดงรายการ token
  console.log('Available tokens count:', tokens.size);
  
  if (earthquakes.length === 0) {
    console.log('No earthquakes to process');
    return { count: 0, quakes: [], filtered: 0 };
  }
  
  if (tokens.size === 0) {
    console.log('No tokens registered - cannot send notifications');
    return { count: 0, quakes: [], filtered: 0 };
  }
  
  // ตรวจสอบการแจ้งเตือน
  let newQuakesCount = 0;
  for (const quake of earthquakes) {
    if (!notifiedEarthquakes.has(quake.id)) {
      newQuakesCount++;
    }
  }
  
  if (newQuakesCount === 0) {
    console.log('All earthquakes have been notified already');
  } else {
    console.log(`Found ${newQuakesCount} new earthquakes that need notifications`);
  }
  
  const notificationResults = {
    count: 0,
    quakes: [],
    filtered: 0,
    filteringDetails: {
      byRegion: 0,
      byMagnitude: 0,
      byDistance: 0
    }
  };
  
  // แสดงรายละเอียดของแต่ละแผ่นดินไหว
  console.log("\nEarthquakes to process:");
  earthquakes.forEach((quake, index) => {
    console.log(`${index + 1}. ID: ${quake.id}, Magnitude: ${quake.properties.mag}, Location: "${quake.properties.place}"`);
  });
  console.log("");
  
  // จัดเตรียมข้อมูลแผ่นดินไหวที่ผ่านเกณฑ์
  const quakesToSend = [];
  
  for (const quake of earthquakes) {
    const quakeId = quake.id;
    
    // ข้ามถ้าเคยส่งแจ้งเตือนแล้ว
    if (hasDeviceBeenNotified(deviceId, quakeId)) {
      console.log(`Earthquake ${quakeId} has been notified already to device ${deviceId}, skipping`);
      continue;
    }
    
    const properties = quake.properties;
    const geometry = quake.geometry;
    
    // ข้ามถ้าไม่มีข้อมูลสำคัญ
    if (!properties.mag || !properties.place) {
      console.log(`Skipping earthquake ${quakeId} - missing magnitude or place data`);
      continue;
    }
    
    // เพิ่มไปยังรายการที่ต้องส่ง
    quakesToSend.push(quake);
  }
  
  // ส่งแจ้งเตือนให้กับทุก token โดยเช็คการตั้งค่าเฉพาะของแต่ละอุปกรณ์
  const tokensArray = Array.from(tokens);
  
  // ตรวจสอบความสัมพันธ์ระหว่าง token กับ device ID
  console.log(`Current token-device mappings: ${tokenToDeviceMap.size}`);
  for (const [token, mappedDeviceId] of tokenToDeviceMap.entries()) {
    console.log(`- Token ${token.substring(0, 8)}... mapped to device: ${mappedDeviceId}`);
  }
  
  // ถ้าระบุ deviceId เฉพาะเจาะจง ให้ส่งเฉพาะอุปกรณ์นั้น
  if (deviceId) {
    console.log(`Sending notifications specifically for device: ${deviceId}`);
    const settings = getDeviceSettings(deviceId);
    
    console.log(`Device ${deviceId} settings: Region filtering: ${settings.filterByRegion ? 'ENABLED' : 'DISABLED'}, region="${settings.defaultRegion}", Magnitude filtering: ${settings.filterByMagnitude ? 'ENABLED' : 'DISABLED'}, min=${settings.minMagnitude}`);
    
    // ตรวจสอบแผ่นดินไหวตามการตั้งค่าของอุปกรณ์นี้
    for (const quake of quakesToSend) {
      const properties = quake.properties;
      const geometry = quake.geometry;
      let shouldSend = true;
      
      // ตรวจสอบตามขนาดแผ่นดินไหว
      if (settings.filterByMagnitude) {
        const magnitude = properties.mag;
        
        if (magnitude < settings.minMagnitude) {
          console.log(`Device ${deviceId}: Filtered out earthquake ${quake.id} (${magnitude}) - below magnitude threshold ${settings.minMagnitude}`);
          notificationResults.filteringDetails.byMagnitude++;
          shouldSend = false;
        }
      }
      
      // ตรวจสอบตามภูมิภาค
      if (shouldSend && settings.filterByRegion && settings.defaultRegion !== 'all') {
        const place = properties.place;
        
        if (!shouldNotifyBasedOnRegion(place, settings.defaultRegion, settings)) {
          console.log(`Device ${deviceId}: Filtered out earthquake ${quake.id} at "${place}" - does not match region "${settings.defaultRegion}"`);
          notificationResults.filteringDetails.byRegion++;
          shouldSend = false;
        }
      }
      
      // ตรวจสอบตามระยะทาง
      if (shouldSend && settings.filterByDistance) {
        const earthquakeLat = geometry.coordinates[1]; // latitude
        const earthquakeLon = geometry.coordinates[0]; // longitude
        
        if (!isWithinDistance(earthquakeLat, earthquakeLon, settings.userLatitude, settings.userLongitude, settings.maxDistanceKm)) {
          const distance = calculateDistance(settings.userLatitude, settings.userLongitude, earthquakeLat, earthquakeLon);
          console.log(`Device ${deviceId}: Filtered out earthquake ${quake.id} - distance ${distance.toFixed(1)}km exceeds limit ${settings.maxDistanceKm}km`);
          if (!notificationResults.filteringDetails.byDistance) {
            notificationResults.filteringDetails.byDistance = 0;
          }
          notificationResults.filteringDetails.byDistance++;
          shouldSend = false;
        } else {
          const distance = calculateDistance(settings.userLatitude, settings.userLongitude, earthquakeLat, earthquakeLon);
          console.log(`Device ${deviceId}: Earthquake ${quake.id} within range - distance ${distance.toFixed(1)}km (limit: ${settings.maxDistanceKm}km)`);
        }
      }
      
      if (shouldSend) {
        // เพิ่ม debugging เพื่อตรวจสอบว่ามี token ถูกต้องหรือไม่
        console.log(`Checking for tokens matching device: ${deviceId}`);
        console.log(`Total tokens: ${tokensArray.length}`);
        
        // หา token ที่เกี่ยวข้องกับ deviceId นี้
        const deviceTokens = [];
        tokensArray.forEach(token => {
          const mappedDeviceId = tokenToDeviceMap.get(token);
          console.log(`Checking token ${token.substring(0, 8)}... mapped to: ${mappedDeviceId || 'none'}`);
          
          if (mappedDeviceId === deviceId) {
            deviceTokens.push(token);
          }
        });
        
        // ถ้าไม่พบ token สำหรับ device นี้ ให้ลองใช้ token ล่าสุดที่ลงทะเบียน (fallback)
        if (deviceTokens.length === 0 && tokensArray.length > 0) {
          console.log(`No tokens found for device ${deviceId}, using most recent token as fallback`);
          deviceTokens.push(tokensArray[tokensArray.length - 1]);
        }
        
        if (deviceTokens.length > 0) {
          console.log(`Found ${deviceTokens.length} tokens for device ${deviceId}`);
          
          for (const token of deviceTokens) {
            // ตรวจสอบว่า token นี้เคยได้รับแจ้งเตือนสำหรับแผ่นดินไหวนี้หรือไม่
            if (!tokenNotifications.has(token)) {
              tokenNotifications.set(token, new Set());
            }
            
            const notifiedQuakes = tokenNotifications.get(token);
            if (notifiedQuakes.has(quake.id)) {
              console.log(`Token ${token.substring(0, 8)}... already notified about earthquake ${quake.id}, skipping`);
              continue;
            }
            
            const message = {
              token: token,
              notification: {
                title: `แผ่นดินไหวขนาด ${properties.mag.toFixed(1)}`,
                body: `เกิดแผ่นดินไหวที่ ${properties.place}`
              },
              data: {
                id: quake.id,
                magnitude: properties.mag.toString(),
                place: properties.place,
                time: new Date(properties.time).toISOString(),
                notification_time: new Date().toISOString(), // เพิ่มเวลาที่ส่งแจ้งเตือน
                latitude: quake.geometry.coordinates[1].toString(),
                longitude: quake.geometry.coordinates[0].toString(),
                depth: quake.geometry.coordinates[2].toString(),
                location: properties.place,
              },
              android: {
                priority: "high",
                notification: {
                  channel_id: "earthquake_alerts",
                  tag: "earthquake_notification",
                  clickAction: "FLUTTER_NOTIFICATION_CLICK",
                  sound: "default",
                  icon: "@mipmap/ic_launcher"
                }
              },
              apns: {
                headers: {
                  "apns-priority": "10"
                },
                payload: {
                  aps: {
                    alert: {
                      title: `แผ่นดินไหวขนาด ${properties.mag.toFixed(1)}`,
                      body: `เกิดแผ่นดินไหวที่ ${properties.place}`
                    },
                    sound: "default",
                    badge: 1,
                    "content-available": 1
                  }
                }
              }
            };
            
            try {
              await admin.messaging().send(message);
              markDeviceAsNotified(deviceId, quake.id);
              notifiedQuakes.add(quake.id); // บันทึกว่า token นี้ได้รับแจ้งเตือนสำหรับแผ่นดินไหวนี้แล้ว
              notificationResults.count++;
              notificationResults.quakes.push({
                id: quake.id,
                magnitude: properties.mag,
                place: properties.place,
                time: new Date(properties.time).toISOString()
              });
              console.log(`Successfully sent notification to device ${deviceId} for earthquake ${quake.id}`);
            } catch (error) {
              console.error(`Error sending notification to device ${deviceId}:`, error);
            }
          }
        } else {
          notificationResults.filtered++;
        }
      }
    }
    
    return notificationResults;
  }
  
  // กรณีส่งแจ้งเตือนให้ทุกอุปกรณ์ โดยตรวจสอบการตั้งค่าของแต่ละอุปกรณ์
  for (const quake of quakesToSend) {
    const quakeId = quake.id;
    const properties = quake.properties;
    const geometry = quake.geometry;
    let notifiedToAnyDevice = false;
    
    console.log(`\nProcessing earthquake: ID=${quakeId}, mag=${properties.mag}, place="${properties.place}"`);
    
    for (const token of tokensArray) {
      try {
        // ดึง device ID ที่เกี่ยวข้องกับ token นี้ (ถ้ามี)
        const deviceIdForToken = tokenToDeviceMap.get(token);
        
        // ถ้ามีการระบุ deviceId เฉพาะ แต่ token ไม่ได้เชื่อมกับ deviceId นั้น ให้ข้าม
        if (deviceId && deviceIdForToken !== deviceId) {
          continue;
        }
        
        const settings = deviceIdForToken ? getDeviceSettings(deviceIdForToken) : globalSettings;
        
        if (deviceIdForToken) {
          console.log(`Processing for device: ${deviceIdForToken} (min magnitude: ${settings.minMagnitude})`);
        } else {
          console.log(`Processing for token without device ID, using global settings (min magnitude: ${settings.minMagnitude})`);
        }
        
        // ตรวจสอบตามขนาดแผ่นดินไหว
        let shouldSend = true;
        
        if (settings.filterByMagnitude) {
          const magnitude = properties.mag;
          
          if (magnitude < settings.minMagnitude) {
            console.log(`Filtered out by magnitude: ${magnitude} < ${settings.minMagnitude}`);
            shouldSend = false;
          }
        }
        
        // ตรวจสอบตามภูมิภาค
        if (shouldSend && settings.filterByRegion && settings.defaultRegion !== 'all') {
          const place = properties.place;
          
          if (!shouldNotifyBasedOnRegion(place, settings.defaultRegion, settings)) {
            console.log(`Filtered out by region: "${place}" does not match "${settings.defaultRegion}"`);
            shouldSend = false;
          }
        }
        
        // ตรวจสอบตามระยะทาง
        if (shouldSend && settings.filterByDistance) {
          const earthquakeLat = geometry.coordinates[1]; // latitude
          const earthquakeLon = geometry.coordinates[0]; // longitude
          
          if (!isWithinDistance(earthquakeLat, earthquakeLon, settings.userLatitude, settings.userLongitude, settings.maxDistanceKm)) {
            const distance = calculateDistance(settings.userLatitude, settings.userLongitude, earthquakeLat, earthquakeLon);
            console.log(`Filtered out by distance: ${distance.toFixed(1)}km exceeds limit ${settings.maxDistanceKm}km`);
            shouldSend = false;
          }
        }
        
        if (!shouldSend) {
          continue; // ข้ามไปที่ token ถัดไป
        }
        
        const message = {
          token: token,
          notification: {
            title: `แผ่นดินไหวขนาด ${properties.mag.toFixed(1)}`,
            body: `เกิดแผ่นดินไหวที่ ${properties.place}`
          },
          data: {
            id: quakeId,
            magnitude: properties.mag.toString(),
            place: properties.place,
            time: new Date(properties.time).toISOString(),
            notification_time: new Date().toISOString(), // เพิ่มเวลาที่ส่งแจ้งเตือน
            latitude: quake.geometry.coordinates[1].toString(),
            longitude: quake.geometry.coordinates[0].toString(),
            depth: quake.geometry.coordinates[2].toString(),
            type: "earthquake",
            location: properties.place,
          },
          android: {
            priority: "high",
            notification: {
              channel_id: "earthquake_alerts",
              tag: "earthquake_notification",
              clickAction: "FLUTTER_NOTIFICATION_CLICK",
              sound: "default",
              icon: "@mipmap/ic_launcher"
            }
          },
          apns: {
            headers: {
              "apns-priority": "10"
            },
            payload: {
              aps: {
                alert: {
                  title: `แผ่นดินไหวขนาด ${properties.mag.toFixed(1)}`,
                  body: `เกิดแผ่นดินไหวที่ ${properties.place}`
                },
                sound: "default",
                badge: 1,
                "content-available": 1
              }
            }
          }
        };
        
        let retries = 0;
        const maxRetries = 3;
        let success = false;
        
        while (!success && retries < maxRetries) {
          try {
            await admin.messaging().send(message);
            success = true;
            notifiedToAnyDevice = true;
            console.log(`Successfully sent notification to token: ${token.substring(0, 8)}...`);
          } catch (error) {
            retries++;
            console.error(`Error sending notification to token ${token.substring(0, 8)}... (attempt ${retries}/${maxRetries}):`, error.message);
            
            // ตรวจสอบว่า token ไม่ถูกต้องหรือไม่
            if (error.code === 'messaging/invalid-registration-token' || 
                error.code === 'messaging/registration-token-not-registered') {
              console.log(`Removing invalid token: ${token.substring(0, 8)}...`);
              tokens.delete(token);
              break; // ออกจากลูป retry ถ้า token ไม่ถูกต้อง
            }
            
            if (retries >= maxRetries) {
              console.error(`Failed to send notification after ${maxRetries} attempts`);
              break;
            }
            
            // รอก่อนลองใหม่
            await new Promise(resolve => setTimeout(resolve, 1000));
          }
        }
      } catch (error) {
        console.error(`Error preparing notification for token ${token.substring(0, 8)}...:`, error);
      }
    }
    
    // บันทึกว่าได้ส่งแล้ว (แม้จะไม่สำเร็จทั้งหมด)
    if (notifiedToAnyDevice) {
      // ใช้ device ID ของอุปกรณ์ปัจจุบันหรือ unknown ถ้าไม่มี
      markDeviceAsNotified(deviceId || 'unknown', quakeId);
      notificationResults.count++;
      notificationResults.quakes.push({
        id: quakeId,
        magnitude: properties.mag,
        place: properties.place,
        time: new Date(properties.time).toISOString()
      });
      
      console.log(`Sent notification for earthquake ${quakeId} to at least one device`);
    }
  }
  
  // สรุปข้อมูลการกรอง
  console.log(`\nFiltering summary: ${notificationResults.filtered} earthquakes filtered out:`);
  console.log(`- ${notificationResults.filteringDetails.byRegion} by region`);
  console.log(`- ${notificationResults.filteringDetails.byMagnitude} by magnitude`);
  console.log(`- ${notificationResults.filteringDetails.byDistance} by distance`);
  
  if (globalSettings.filterByRegion || globalSettings.filterByMagnitude) {
    console.log(`\nFiltering summary (global settings):`);
    
    if (globalSettings.filterByRegion) {
      console.log(`- ${notificationResults.filteringDetails?.byRegion || 0} earthquakes filtered by region "${globalSettings.defaultRegion}"`);
    }
    
    if (globalSettings.filterByMagnitude) {
      console.log(`- ${notificationResults.filteringDetails?.byMagnitude || 0} earthquakes filtered by magnitude < ${globalSettings.minMagnitude}`);
    }
    
    if (globalSettings.filterByDistance) {
      console.log(`- ${notificationResults.filteringDetails?.byDistance || 0} earthquakes filtered by distance > ${globalSettings.maxDistanceKm}km`);
    }
    
    console.log(`- Total filtered: ${notificationResults.filtered || 0} earthquakes`);
  }
  
  return notificationResults;
}

// ฟังก์ชันตรวจสอบแผ่นดินไหวและส่งการแจ้งเตือน
async function checkEarthquakesAndNotify() {
  // ดึงรายการ deviceIds ทั้งหมดที่มีการลงทะเบียน
  const registeredDeviceIds = Object.keys(deviceSettings);
  
  console.log(`Checking for new earthquakes at ${new Date().toISOString()}...`);
  const earthquakes = await fetchEarthquakes();
  
  // แสดงข้อมูลแผ่นดินไหวที่ดึงมา
  if (earthquakes.length > 0) {
    console.log(`Fetched ${earthquakes.length} earthquakes:`);
    earthquakes.forEach((quake, index) => {
      if (index < 10) { // จำกัดการแสดงผล
        console.log(`  ${index + 1}. Mag ${quake.properties.mag.toFixed(1)} at ${quake.properties.place}`);
      }
    });
    if (earthquakes.length > 10) {
      console.log(`  ... and ${earthquakes.length - 10} more earthquakes`);
    }
  }
  
  // ส่งการแจ้งเตือนให้กับแต่ละอุปกรณ์ที่ลงทะเบียน
  let totalNotifications = 0;
  
  if (registeredDeviceIds.length > 0) {
    console.log(`Sending notifications to ${registeredDeviceIds.length} registered devices`);
    
    for (const deviceId of registeredDeviceIds) {
      const result = await sendNotifications(earthquakes, deviceId);
      totalNotifications += result.count;
    }
    
    if (totalNotifications > 0) {
      console.log(`Sent a total of ${totalNotifications} notifications to all devices`);
    } else {
      console.log('No new notifications sent to any devices');
    }
  } else {
    // ถ้าไม่มีอุปกรณ์ลงทะเบียน ให้ใช้ค่า global settings ตามเดิม
    const result = await sendNotifications(earthquakes, null);
    
    if (result.count > 0) {
      console.log(`Sent notifications for ${result.count} new earthquakes using global settings`);
    } else {
      console.log('No new earthquakes found or all have been notified already');
    }
    
    if (globalSettings.filterByRegion || globalSettings.filterByMagnitude) {
      console.log(`\nFiltering summary (global settings):`);
      
      if (globalSettings.filterByRegion) {
        console.log(`- ${result.filteringDetails?.byRegion || 0} earthquakes filtered by region "${globalSettings.defaultRegion}"`);
      }
      
      if (globalSettings.filterByMagnitude) {
        console.log(`- ${result.filteringDetails?.byMagnitude || 0} earthquakes filtered by magnitude < ${globalSettings.minMagnitude}`);
      }
      
      if (globalSettings.filterByDistance) {
        console.log(`- ${result.filteringDetails?.byDistance || 0} earthquakes filtered by distance > ${globalSettings.maxDistanceKm}km`);
      }
      
      console.log(`- Total filtered: ${result.filtered || 0} earthquakes`);
    }
  }
}

// ตั้งเวลาตรวจสอบแผ่นดินไหวทุก X นาที
console.log(`Setting up cron job to check earthquakes every ${globalSettings.checkIntervalMinutes} minutes`);
let cronJob = cron.schedule(`*/${globalSettings.checkIntervalMinutes} * * * *`, () => {
  console.log(`Cron job triggered at ${new Date().toISOString()}`);
  checkEarthquakesAndNotify();
});

// ทดสอบ cron job เพิ่มเติมในช่วงแรก
setTimeout(() => {
  console.log('Running additional check after 2 minutes...');
  checkEarthquakesAndNotify();
}, 2 * 60 * 1000);

setTimeout(() => {
  console.log('Running additional check after 4 minutes...');
  checkEarthquakesAndNotify();
}, 4 * 60 * 1000);

// ทดสอบความถูกต้องของทุก token ทุกวัน
setInterval(async () => {
  if (tokens.size === 0) return;
  
  console.log(`Validating ${tokens.size} tokens...`);
  const tokensArray = Array.from(tokens);
  const invalidTokens = [];
  
  for (const token of tokensArray) {
    try {
      // ส่งข้อความเงียบเพื่อตรวจสอบความถูกต้องของ token
      await admin.messaging().send({
        token: token,
        data: { type: 'ping', timestamp: Date.now().toString() }
      });
    } catch (error) {
      if (error.code === 'messaging/invalid-registration-token' || 
          error.code === 'messaging/registration-token-not-registered') {
        invalidTokens.push(token);
      }
    }
  }
  
  // ลบ token ที่ไม่ถูกต้องออก
  if (invalidTokens.length > 0) {
    console.log(`Removing ${invalidTokens.length} invalid tokens`);
    invalidTokens.forEach(token => tokens.delete(token));
  } else {
    console.log('All tokens are valid');
  }
}, 24 * 60 * 60 * 1000); // ทำวันละครั้ง

// ลิมิตจำนวนแผ่นดินไหวที่จำไว้เพื่อป้องกันการใช้หน่วยความจำมากเกินไป
setInterval(() => {
  if (notifiedEarthquakes.size > 1000) {
    // เก็บเฉพาะ 500 รายการล่าสุด
    const arr = Array.from(notifiedEarthquakes);
    const newSet = new Set(arr.slice(arr.length - 500));
    notifiedEarthquakes.clear();
    arr.slice(arr.length - 500).forEach(id => notifiedEarthquakes.add(id));
    console.log(`Pruned notified earthquakes list from ${arr.length} to ${newSet.size} items`);
  }
}, 24 * 60 * 60 * 1000); // ทำวันละครั้ง

// เริ่มเซิร์ฟเวอร์
const PORT = process.env.PORT || 6969;
app.listen(PORT, () => {
  console.log(`Server running on port ${PORT}`);
  
  // ตรวจสอบแผ่นดินไหวทันทีเมื่อเริ่มต้นเซิร์ฟเวอร์
  if (globalSettings.autoCheckOnStartup) {
    console.log('Performing initial earthquake check on startup...');
    checkEarthquakesAndNotify();
  }
});

// สร้าง endpoint สำหรับการลงทะเบียน device
app.post('/register-device', (req, res) => {
  try {
    const { deviceId, token } = req.body;
    
    if (!deviceId || !token) {
      return res.status(400).json({ error: 'Device ID and token are required' });
    }
    
    // บันทึก device ID และผูก token
    if (!deviceSettings[deviceId]) {
      deviceSettings[deviceId] = {
        ...globalSettings,
        deviceId
      };
    }
    
    // บันทึก token
    tokens.add(token);
    
    // สร้างการผูกระหว่าง token กับ device ID
    tokenToDeviceMap.set(token, deviceId);
    
    console.log(`Registered device ${deviceId} with token ${token.substring(0, 8)}...`);
    
    res.status(200).json({
      message: 'Device registered successfully',
      settings: deviceSettings[deviceId]
    });
  } catch (error) {
    console.error('Error registering device:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// สร้าง endpoint สำหรับดึงการตั้งค่าของอุปกรณ์
app.get('/device-settings/:deviceId', (req, res) => {
  try {
    const { deviceId } = req.params;
    
    if (!deviceId) {
      return res.status(400).json({ error: 'Device ID is required' });
    }
    
    const settings = getDeviceSettings(deviceId);
    
    res.status(200).json({
      deviceId,
      settings
    });
  } catch (error) {
    console.error('Error getting device settings:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// ล้างประวัติการแจ้งเตือนเก่า (ทำทุก 24 ชั่วโมง)
setInterval(() => {
  if (tokenNotifications.size > 0) {
    console.log(`Cleaning up token notification history (${tokenNotifications.size} tokens)`);
    tokenNotifications.clear();
  }
}, 24 * 60 * 60 * 1000);

// ลบแผ่นดินไหวถ้าเคยส่งแจ้งเตือนไปยังอุปกรณ์นี้แล้ว
function hasDeviceBeenNotified(deviceId, earthquakeId) {
  if (!deviceId) return false;
  
  // สร้าง set สำหรับ device นี้ถ้ายังไม่มี
  if (!deviceNotifiedEarthquakes.has(deviceId)) {
    deviceNotifiedEarthquakes.set(deviceId, new Set());
  }
  
  // ตรวจสอบว่า device นี้เคยได้รับการแจ้งเตือนแผ่นดินไหวนี้หรือไม่
  return deviceNotifiedEarthquakes.get(deviceId).has(earthquakeId);
}

// บันทึกการแจ้งเตือนสำหรับอุปกรณ์นี้
function markDeviceAsNotified(deviceId, earthquakeId) {
  if (!deviceId) return;
  
  // สร้าง set สำหรับ device นี้ถ้ายังไม่มี
  if (!deviceNotifiedEarthquakes.has(deviceId)) {
    deviceNotifiedEarthquakes.set(deviceId, new Set());
  }
  
  // บันทึกว่า device นี้ได้รับการแจ้งเตือนแผ่นดินไหวนี้แล้ว
  deviceNotifiedEarthquakes.get(deviceId).add(earthquakeId);
  
  // ยังคงบันทึกลงใน global set เดิมเพื่อความเข้ากันได้กับโค้ดเดิม
  notifiedEarthquakes.add(earthquakeId);
}

// ใหม่: API สำหรับทดสอบการคำนวณระยะทาง
app.post('/test-distance', (req, res) => {
  const { lat1, lon1, lat2, lon2, deviceId } = req.body;
  
  if (!lat1 || !lon1 || !lat2 || !lon2) {
    return res.status(400).json({ 
      error: 'lat1, lon1, lat2, lon2 are required' 
    });
  }
  
  try {
    const distance = calculateDistance(
      parseFloat(lat1), 
      parseFloat(lon1), 
      parseFloat(lat2), 
      parseFloat(lon2)
    );
    
    let withinRange = null;
    let settings = null;
    
    if (deviceId) {
      settings = getDeviceSettings(deviceId);
      if (settings.filterByDistance && settings.maxDistanceKm) {
        withinRange = distance <= settings.maxDistanceKm;
      }
    }
    
    return res.json({
      success: true,
      distance: parseFloat(distance.toFixed(2)),
      distanceKm: `${distance.toFixed(1)} km`,
      coordinates: {
        point1: { latitude: parseFloat(lat1), longitude: parseFloat(lon1) },
        point2: { latitude: parseFloat(lat2), longitude: parseFloat(lon2) }
      },
      deviceSettings: settings ? {
        maxDistanceKm: settings.maxDistanceKm,
        filterByDistance: settings.filterByDistance,
        withinRange: withinRange
      } : null
    });
  } catch (error) {
    console.error('Error calculating distance:', error);
    return res.status(500).json({ 
      success: false, 
      error: error.message 
    });
  }
});
