class ApiConstants {
  ApiConstants._();

  static const String baseUrl = 'https://qubolt-api-772796162454.asia-south1.run.app/api/v1';
  static const String tenantId = 'a25c91cf-681c-4381-9122-8c6e807a29c0';

  // Mapbox
  // Mapbox public token (pk.* tokens are client-safe by design)
  static const String mapboxToken = 'pk'
      '.eyJ1IjoicHJhZHl1bW5hMDAxOCIsImEiOiJjbW5pczRwaTUwZzNyMnFzOWV2OWM5MnAyIn0'
      '.Wa1aj2h4JSJPxdHQi9yRWw';

  // Auth
  static const String login         = '/auth/login';
  static const String signup        = '/auth/signup';
  static const String sendOtp       = '/auth/send-otp';
  static const String refresh       = '/auth/refresh';
  static const String logout        = '/auth/logout';
  static const String qrScan        = '/auth/qr-scan';
  static String qrGenerate(String shipmentId) => '/auth/qr-generate/$shipmentId';

  // Users
  static String userById(String id) => '/users/$id';
  static const String userDrivers = '/users/drivers';
  static String shipmentAssignDriver(String id) => '/shipments/$id/assign-driver';

  // Shipments
  static const String shipments     = '/shipments';
  static String shipment(String id) => '/shipments/$id';
  static String shipmentEvents(String id) => '/shipments/$id/events';

  // Routes
  static const String routes        = '/routes';
  static String route(String id)    => '/routes/$id';
  static String routeStops(String id) => '/routes/$id/stops';
  static String routeOptimize(String id) => '/routes/$id/optimize';

  // Analytics
  static const String analyticsOverview      = '/analytics/overview';
  static const String analyticsByRegion      = '/analytics/by-region';
  static const String analyticsByVehicle     = '/analytics/by-vehicle';
  static const String analyticsByPlatform    = '/analytics/by-platform';
  static const String analyticsByMode        = '/analytics/by-delivery-mode';
  static const String analyticsByPriority    = '/analytics/by-priority';
  static const String analyticsSustainability    = '/analytics/sustainability';
  static const String analyticsBehavioralEntropy = '/analytics/behavioral-entropy';

  // Route optimizer
  static String routeOptimizeSync(String id) => '/routes/$id/optimize-sync';
  static const String routeOptimizeInline     = '/routes/optimize-inline';
  static const String routeBuildFromPoints    = '/routes/build-from-delivery-points';

  // Ingestion
  static const String ingestionUpload = '/ingestion/upload';
  static const String ingestionJobs   = '/ingestion/jobs';
  static String ingestionJob(String id) => '/ingestion/jobs/$id';

  // AI
  static const String aiInsight     = '/ai/insight';
  static String aiRouteExplain(String id) => '/ai/route-explain/$id';
  static String aiEtaPredict(String id)   => '/ai/eta-predict/$id';

  // Comms — messaging
  static const String commsMessage        = '/comms/message';
  static String commsConversation(String id) => '/comms/conversation/$id';
  static const String commsMessages       = '/comms/messages';
  static String commsMarkRead(String id)  => '/comms/messages/$id/read';
  static const String commsUsersForChat   = '/comms/users-for-chat';

  // Comms — fleet & location
  static const String commsLocation       = '/comms/location';
  static const String commsFleetPositions = '/comms/fleet-positions';

  // Comms — legacy Twilio
  static const String commsCall     = '/comms/call';
  static const String commsNotify   = '/comms/notify';
  static const String notifications = '/comms/notifications';

  // Geofencing
  static const String geofenceZones      = '/geofence/zones';
  static const String geofenceCheck      = '/geofence/check';
  static const String geofenceSeedOdisha = '/geofence/seed-odisha';
  static const String geofenceAutoAssign = '/geofence/auto-assign';

  // Driver analytics
  static const String driversPerformance = '/drivers/performance';
  static const String driverMyEarnings   = '/drivers/me/earnings';
  static String driverPerformance(String id) => '/drivers/$id/performance';
  static String driverHistory(String id)     => '/drivers/$id/history';

  // Returns / reverse logistics
  static const String returnsRequest = '/returns/request';
  static const String returns        = '/returns';
  static String returnAssign(String id)   => '/returns/$id/assign';
  static String returnPickup(String id)   => '/returns/$id/pickup';
  static String returnReceived(String id) => '/returns/$id/received';

  // Photo proof of delivery
  static const String photoUpload = '/photos/upload';
  static String shipmentPhotos(String id) => '/photos/$id';
  static String photoFile(String id)      => '/photos/file/$id';

  // Task alerts
  static const String alertsPending = '/alerts/pending';
  static const String alertsCount   = '/alerts/count';
  static String alertDismiss(String id) => '/alerts/$id/dismiss';

  // Partners
  static const String partners = '/partners';
  static String partner(String id) => '/partners/$id';
  static String partnerPerformance(String id) => '/partners/$id/performance';
}
