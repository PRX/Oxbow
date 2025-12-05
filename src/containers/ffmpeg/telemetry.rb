require "aws-sdk-cloudwatch"

CLOUDWATCH = Aws::CloudWatch::Client.new

def send_start_metric
  # Count the tasks in CloudWatch Metrics
  CLOUDWATCH.put_metric_data({
    namespace: "PRX/Oxbow",
    metric_data: [
      {
        metric_name: "FFmpegExecutions",
        dimensions: [
          {
            name: "StateMachineName",
            value: ENV["STATE_MACHINE_NAME"]
          }
        ],
        value: 1,
        unit: "Count"
      }
    ]
  })
end

def send_end_metric(duration)
  # Record FFmpeg duration in CloudWatch Metrics
  CLOUDWATCH.put_metric_data({
    namespace: "PRX/Oxbow",
    metric_data: [
      {
        metric_name: "FFmpegDuration",
        dimensions: [
          {
            name: "StateMachineName",
            value: ENV["STATE_MACHINE_NAME"]
          }
        ],
        value: duration,
        unit: "Seconds"
      }
    ]
  })
end
