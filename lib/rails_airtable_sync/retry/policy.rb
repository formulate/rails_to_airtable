module RailsAirtableSync
  module Retry
    # Wraps a block with configurable retry logic supporting exponential,
    # linear, and constant backoff with optional jitter.
    #
    # Retryable errors (by default):
    #   - TransportError (timeouts, connection failures)
    #   - RateLimitError (HTTP 429)
    #   - ApiError where retryable? == true (5xx)
    class Policy
      RETRYABLE_ERRORS = [TransportError, RateLimitError].freeze

      def initialize(config)
        @config = config
      end

      # Execute the given block, retrying on retryable errors.
      # Raises the last error if all retries are exhausted.
      def with_retry
        attempt = 0

        begin
          attempt += 1
          yield
        rescue *RETRYABLE_ERRORS => e
          raise if attempt > @config.max_retries

          delay = backoff_delay(attempt)
          @config.logger.warn(
            "[RailsAirtableSync] Retryable error (attempt #{attempt}/#{@config.max_retries}): " \
            "#{e.class}: #{e.message}. Retrying in #{delay.round(2)}s..."
          )
          sleep(delay)
          retry
        rescue ApiError => e
          raise unless e.retryable? && attempt <= @config.max_retries

          delay = backoff_delay(attempt)
          @config.logger.warn(
            "[RailsAirtableSync] Retryable API error #{e.status} (attempt #{attempt}): " \
            "#{e.message}. Retrying in #{delay.round(2)}s..."
          )
          sleep(delay)
          retry
        end
      end

      # Returns true if the given error should trigger a retry.
      def retryable?(error)
        case error
        when *RETRYABLE_ERRORS then true
        when ApiError          then error.retryable?
        else false
        end
      end

      private

      def backoff_delay(attempt)
        base = case @config.retry_backoff
               when :exponential then (2**(attempt - 1)).to_f
               when :linear      then attempt.to_f
               when :constant    then 1.0
               else 1.0
               end

        jitter = @config.retry_jitter ? rand * 0.5 : 0
        base + jitter
      end
    end
  end
end
