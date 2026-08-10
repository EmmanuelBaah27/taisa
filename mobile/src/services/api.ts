import axios from 'axios';
import * as SecureStore from 'expo-secure-store';

const BASE_URL = process.env.EXPO_PUBLIC_API_URL || 'http://localhost:3000/api/v1';

const api = axios.create({ baseURL: BASE_URL, timeout: 90000 });

// Inject user ID header on every request
api.interceptors.request.use(async (config) => {
  const userId = await SecureStore.getItemAsync('userId');
  if (userId) config.headers['x-user-id'] = userId;
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
