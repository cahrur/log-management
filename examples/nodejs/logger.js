/**
 * Pino JSON Logger - Setup untuk Pantra
 *
 * Install: npm install pino pino-pretty
 *
 * Pino output JSON ke stdout, yang otomatis di-capture Docker
 * dan di-pickup Promtail.
 *
 * Usage:
 *   const logger = require('./logger');
 *   logger.info({ userId: 123, action: 'login' }, 'User logged in');
 *   logger.error({ err, requestId }, 'Request failed');
 */

const pino = require('pino');

const logger = pino({
  level: process.env.LOG_LEVEL || 'info',

  // Format timestamp ISO 8601
  timestamp: pino.stdTimeFunctions.isoTime,

  // Base fields yang selalu ada di setiap log
  base: {
    service: process.env.SERVICE_NAME || 'node-api',
    env: process.env.NODE_ENV || 'development',
    host: process.env.HOSTNAME || require('os').hostname(),
  },

  // Serializers untuk object umum
  serializers: {
    // Error serializer - include stack trace
    err: pino.stdSerializers.err,

    // Request serializer
    req: (req) => ({
      method: req.method,
      url: req.url,
      headers: {
        host: req.headers.host,
        'user-agent': req.headers['user-agent'],
        'x-request-id': req.headers['x-request-id'],
      },
      remoteAddress: req.socket?.remoteAddress,
    }),

    // Response serializer
    res: (res) => ({
      statusCode: res.statusCode,
    }),
  },

  // Redact sensitive fields
  redact: {
    paths: ['req.headers.authorization', 'req.headers.cookie', 'password', 'token'],
    censor: '[REDACTED]',
  },

  // Pretty print di development
  transport:
    process.env.NODE_ENV !== 'production'
      ? { target: 'pino-pretty', options: { colorize: true } }
      : undefined,
});

/**
 * Express/Fastify request logger middleware
 *
 * Usage (Express):
 *   const { requestLogger } = require('./logger');
 *   app.use(requestLogger);
 */
const requestLogger = (req, res, next) => {
  const start = Date.now();
  const requestId = req.headers['x-request-id'] || crypto.randomUUID();

  // Attach logger ke request
  req.log = logger.child({ requestId });

  res.on('finish', () => {
    const duration = Date.now() - start;
    const level = res.statusCode >= 500 ? 'error' : res.statusCode >= 400 ? 'warn' : 'info';

    req.log[level](
      {
        req,
        res,
        duration_ms: duration,
      },
      `${req.method} ${req.url} ${res.statusCode} ${duration}ms`
    );
  });

  next();
};

module.exports = logger;
module.exports.requestLogger = requestLogger;
