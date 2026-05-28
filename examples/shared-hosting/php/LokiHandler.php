<?php
/**
 * LokiHandler - Monolog handler that pushes logs to Loki HTTP API.
 * 
 * For shared hosting environments where you can't install Promtail.
 * Copy this file to your Laravel app: app/Logging/LokiHandler.php
 *
 * @see https://github.com/cahrur/pantra/blob/main/SHARED-HOSTING.md
 */

namespace App\Logging;

use Monolog\Handler\AbstractProcessingHandler;
use Monolog\Level;
use Monolog\LogRecord;

class LokiHandler extends AbstractProcessingHandler
{
    private string $lokiUrl;
    private string $username;
    private string $password;
    private array $labels;
    private array $buffer = [];
    private int $batchSize;

    public function __construct(
        string $lokiUrl,
        string $username = '',
        string $password = '',
        array $labels = [],
        int $batchSize = 10,
        Level $level = Level::Debug,
        bool $bubble = true
    ) {
        parent::__construct($level, $bubble);
        $this->lokiUrl = rtrim($lokiUrl, '/') . '/loki/api/v1/push';
        $this->username = $username;
        $this->password = $password;
        $this->labels = $labels;
        $this->batchSize = $batchSize;

        register_shutdown_function([$this, 'flush']);
    }

    protected function write(LogRecord $record): void
    {
        $this->buffer[] = $record;

        if (count($this->buffer) >= $this->batchSize) {
            $this->flush();
        }
    }

    public function flush(): void
    {
        if (empty($this->buffer)) {
            return;
        }

        // Group entries by label set for better Loki performance
        $grouped = [];
        foreach ($this->buffer as $record) {
            $labels = array_merge($this->labels, [
                'level' => strtolower($record->level->name),
                'channel' => $record->channel,
            ]);

            $message = $record->formatted ?? $record->message;
            if (!empty($record->context)) {
                $message .= ' ' . json_encode($record->context);
            }

            $key = json_encode($labels);
            if (!isset($grouped[$key])) {
                $grouped[$key] = ['stream' => $labels, 'values' => []];
            }
            $grouped[$key]['values'][] = [
                (string)(intval($record->datetime->format('U.u') * 1e9)),
                $message,
            ];
        }

        $payload = json_encode(['streams' => array_values($grouped)]);
        $this->send($payload);
        $this->buffer = [];
    }

    private function send(string $payload): void
    {
        $ch = curl_init($this->lokiUrl);
        $headers = ['Content-Type: application/json'];

        curl_setopt_array($ch, [
            CURLOPT_POST => true,
            CURLOPT_POSTFIELDS => $payload,
            CURLOPT_HTTPHEADER => $headers,
            CURLOPT_TIMEOUT => 3,
            CURLOPT_CONNECTTIMEOUT => 2,
            CURLOPT_RETURNTRANSFER => true,
        ]);

        if ($this->username && $this->password) {
            curl_setopt($ch, CURLOPT_USERPWD, $this->username . ':' . $this->password);
        }

        curl_exec($ch);
        curl_close($ch);
    }
}
