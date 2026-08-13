import axios from 'axios';
import { getInstallationId } from './installationIdentity';
import { getDeviceCredential } from './deviceEnrollment';

const BASE_URL = process.env.EXPO_PUBLIC_API_URL || 'http://localhost:3000/api/v1';

const api = axios.create({ baseURL: BASE_URL, timeout: 90000 });

// Device installation ID is a rate-limit key, not profile identity or authentication.
api.interceptors.request.use(async (config) => {
  config.headers['x-user-id'] = await getInstallationId();
  const credential = await getDeviceCredential();
  if (credential !== null) config.headers.Authorization = `Bearer ${credential}`;
  return config;
});

api.interceptors.response.use(
  (response) => response,
  (error) => {
    // Request/response bodies and provider messages may contain private work content.
    // Transport callers convert this into content-free, user-facing errors.
    return Promise.reject(error);
  }
);

export default api;
