const { withEntitlementsPlist } = require('expo/config-plugins');

/**
 * Taisa schedules local, privacy-safe reminders only. Removing the remote-push entitlement keeps
 * physical-device development builds compatible with Apple Personal Teams.
 */
module.exports = function withLocalNotificationsOnly(config) {
  return withEntitlementsPlist(config, (mod) => {
    delete mod.modResults['aps-environment'];
    return mod;
  });
};
