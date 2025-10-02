#!/bin/ruby

# The following environment variables are passed in as ContainerOverrides when
# the state machine runs the ECS task
# STATE_MACHINE_ARN
# STATE_MACHINE_NAME
# STATE_MACHINE_EXECUTION_ID
# STATE_MACHINE_JOB_ID
# STATE_MACHINE_TASK_INDEX
# STATE_MACHINE_S3_DESTINATION_WRITER_ROLE
# STATE_MACHINE_AWS_REGION
# STATE_MACHINE_ARTIFACT_BUCKET_NAME
# STATE_MACHINE_FFMPEG_TASK_JSON

require "aws-sdk-cloudwatch"
require "aws-sdk-s3"
require "aws-sdk-sts"

require "json"

class String
  def underscore
    gsub("::", "/")
      .gsub(/([A-Z]+)([A-Z][a-z])/, '\1_\2')
      .gsub(/([a-z\d])([A-Z])/, '\1_\2')
      .tr("-", "_")
      .downcase
  end
end

cloudwatch = Aws::CloudWatch::Client.new

start_time = Time.now.to_i

task_details = JSON.parse(ENV["STATE_MACHINE_FFMPEG_TASK_JSON"])
ffmpeg_global_opts = task_details["GlobalOptions"]
ffmpeg_inputs = task_details["Inputs"]

outputs = task_details["Outputs"]

# Count the tasks in CloudWatch Metrics
cloudwatch.put_metric_data({
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

# Execute the command
ffmpeg_outputs = outputs.each_with_index.map { |o, idx| "#{o["Options"]} -f #{o["Format"]} output-#{idx}.file" }.join(" ")
ffmpeg_cmd = [
  "ffmpeg",
  ffmpeg_global_opts,
  ffmpeg_inputs.to_s,
  ffmpeg_outputs.to_s
].join(" ")

puts "Calling FFmpeg"
puts ffmpeg_cmd

raise StandardError, "FFmpeg failed" unless system ffmpeg_cmd

end_time = Time.now.to_i
duration = end_time - start_time

# We can use a single S3 TransferManager to PUT all probes
put_probe_s3_client = Aws::S3::Client.new(region: ENV["STATE_MACHINE_AWS_REGION"])
put_probe_s3tm = Aws::S3::TransferManager.new(client: put_probe_s3_client)

outputs.each_with_index do |output, idx|
  # Probe the outputs of the command
  ffprobe_cmd = [
    "ffprobe",
    "-v error",
    "-show_streams",
    "-show_format",
    "-i output-#{idx}.file",
    "-print_format json",
    "> ffprobe-#{idx}.json"
  ].join(" ")

  raise StandardError, "FFmpeg probe failed" unless system ffprobe_cmd

  # Write the probe output to S3
  puts "Writing probe output to S3 artifact bucket"
  bucket_name = ENV["STATE_MACHINE_ARTIFACT_BUCKET_NAME"]
  object_key = "#{ENV["STATE_MACHINE_EXECUTION_ID"]}/ffmpeg/ffprobe-#{ENV["STATE_MACHINE_TASK_INDEX"]}-#{idx}.json"
  put_probe_s3tm.upload_file("ffprobe-#{idx}.json", bucket: bucket_name, key: object_key)

  destination = output["Destination"]

  if destination["Mode"] == "AWS/S3"
    region = ENV["STATE_MACHINE_AWS_REGION"]

    sts = Aws::STS::Client.new(endpoint: "https://sts.#{region}.amazonaws.com")

    # Assume a role that will have access to the S3 destination bucket, and use
    # that role's credentials for the S3 upload
    role = sts.assume_role({
      role_arn: ENV["STATE_MACHINE_S3_DESTINATION_WRITER_ROLE"],
      role_session_name: "oxbow_ffmpeg_task"
    })

    credentials = Aws::Credentials.new(
      role.credentials.access_key_id,
      role.credentials.secret_access_key,
      role.credentials.session_token
    )

    # The Ruby AWS SDK does not intelligently handle cases where the client isn't
    # explicitly set for the region where the bucket exists. We have to detect
    # the region using HeadBucket, and then create the client with the returned
    # region.
    # TODO This isn't necessary when the bucket and the client are in the same
    # region. It would be possible to catch the error and do the lookup only when
    # necessary.

    # Create a client with permission to HeadBucket
    begin
      s3_writer = Aws::S3::Client.new(credentials: credentials, endpoint: "https://s3.amazonaws.com")
      bucket_head = s3_writer.head_bucket({bucket: ENV["STATE_MACHINE_DESTINATION_BUCKET_NAME"]})
      bucket_region = bucket_head.context.http_response.headers["x-amz-bucket-region"]
    rescue Aws::S3::Errors::Http301Error, Aws::S3::Errors::PermanentRedirect => e
      bucket_region = e.context.http_response.headers["x-amz-bucket-region"]
    end

    puts "Destination bucket in region: #{bucket_region}"

    # Create a new client with the permissions and the correct region
    s3_writer = Aws::S3::Client.new(credentials: credentials, region: bucket_region)

    put_object_params = {}

    # When the optional `ContentType` property is set to `REPLACE`, if a MIME is
    # included with the artifact, that should be used as the new file's
    # content type
    if destination["ContentType"] == "REPLACE" && artifact.dig("Descriptor", "MIME")
      put_object_params[:content_type] = artifact["Descriptor"]["MIME"]
    end

    # For historical reasons, the available parameters match ALLOWED_UPLOAD_ARGS
    # from Boto3's S3Transfer class.
    # https://boto3.amazonaws.com/v1/documentation/api/latest/reference/customizations/s3.html
    # If any parameters are included on the destination config, they are
    # reformatted to snake case, and added to the put_object params as symbols.
    if destination.key?("Parameters")
      destination["Parameters"].each do |k, v|
        put_object_params[k.underscore.to_sym] = v
      end
    end

    put_object_params[:bucket] = ENV["STATE_MACHINE_DESTINATION_BUCKET_NAME"]
    put_object_params[:key] = ENV["STATE_MACHINE_DESTINATION_OBJECT_KEY"]

    # Upload the encoded file to the S3
    puts "Writing output to S3 destination"
    put_ouput_s3tm = Aws::S3::TransferManager.new(client: s3_writer)
    put_ouput_s3tm.upload_file("output-#{idx}.file", **put_object_params)
  end
end

# Record FFmpeg duration in CloudWatch Metrics
cloudwatch.put_metric_data({
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
