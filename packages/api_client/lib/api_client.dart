library api_client;

// Config
export 'src/config/api_config.dart';

// HTTP
export 'src/http/auth_interceptor.dart';
export 'src/http/dio_client.dart';
export 'src/http/logging_interceptor.dart';
export 'src/http/token_storage.dart';

// Models
export 'src/models/api_exception.dart';
export 'src/models/api_response.dart';
export 'src/models/auth_dtos.dart';
export 'src/models/auth_error_mapper.dart';
export 'src/models/support_dtos.dart';
export 'src/models/user_dtos.dart';
export 'src/models/verification_dtos.dart';

// Realtime
export 'src/realtime/chat_controller.dart';
export 'src/realtime/chat_outbox.dart';
export 'src/realtime/chat_realtime.dart';

// Services
export 'src/services/category_service.dart';
export 'src/services/chat_service.dart';
export 'src/services/help_service.dart';
export 'src/services/job_service.dart';
export 'src/services/legal_service.dart';
export 'src/services/location_service.dart';
export 'src/services/loyalty_service.dart';
export 'src/services/media_service.dart';
export 'src/services/notification_service.dart';
export 'src/services/payment_service.dart';
export 'src/services/rating_service.dart';
export 'src/services/ride_service.dart';
export 'src/services/safety_service.dart';
export 'src/services/support_service.dart';
export 'src/services/user_service.dart';
export 'src/services/socket_service.dart';
export 'src/services/verification_service.dart';

// Auth
export 'src/auth/auth_models.dart';
export 'src/auth/auth_service.dart';
export 'src/auth/device_id.dart';
export 'src/auth/mock_auth_service.dart';
export 'src/auth/real_auth_service.dart';
