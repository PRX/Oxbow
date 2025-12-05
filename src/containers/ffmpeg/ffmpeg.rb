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
# STATE_MACHINE_TASK_TOKEN
# STATE_MACHINE_TASK_TYPE

require "aws-sdk-cloudwatch"
require "aws-sdk-s3"
require "aws-sdk-states"
require "aws-sdk-sts"

require "json"
require "time"

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
sf = Aws::States::Client.new

begin
  task_result = {
    Task: ENV["STATE_MACHINE_TASK_TYPE"],
    FFmpeg: {
      Ouputs: []
    }
  }

  start_time = Time.now.to_i

  task_details = JSON.parse(ENV["STATE_MACHINE_FFMPEG_TASK_JSON"])
  # Global options is a string like `-loglevel info`
  ffmpeg_global_opts = task_details["GlobalOptions"]
  # Inputs is a string like `-t 3900 -i "https://example.com/live-radio.aac"`
  ffmpeg_inputs = task_details["Inputs"]

  # Outputs is an array of objects like:
  # [
  #   { "Format": "flac", "Options": "-sample_fmt s16 -ar 48000", "Destination": {…} },
  #   { "Format": "mp3", "Options": "-sample_fmt s16 -ar 44100", "Destination": {…} }
  # ]
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

    stdout, _stderr, status = Open3.capture3(ffprobe_cmd)

    unless status.success?
      raise StandardError, "FFmpeg probe failed"
    end

    probe_results = JSON.parse(stdout)

    # Add the probe results for this output to the task result
    task_result[:FFmpeg][:Outputs].push({
      Mode: output["Destination"]["Mode"],
      BucketName: output["Destination"]["BucketName"],
      ObjectKey: output["Destination"]["ObjectKey"],
      Duration: probe_results["format"]["duration"].to_f * 1000,
      Size: probe_results["format"]["size"].to_f
    })

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
        bucket_head = s3_writer.head_bucket({bucket: destination["BucketName"]})
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

      put_object_params[:bucket] = destination["BucketName"]
      put_object_params[:key] = destination["ObjectKey"]

      # Upload the encoded file to the S3
      puts "Writing output to S3 destination"
      put_ouput_s3tm = Aws::S3::TransferManager.new(client: s3_writer)
      put_ouput_s3tm.upload_file("output-#{idx}.file", **put_object_params)
    end
  end

  now = Time.now
  task_result["Time"] = now.getutc.iso8601
  task_result["Timestamp"] = now.to_i

  # TODO log this result
  sf.send_task_success({
    task_token: ENV["TASK_TOKEN"],
    output: task_result.to_json
  })

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
rescue => e
  sf.send_task_failure({
    task_token: ENV["TASK_TOKEN"],
    error: e.class,
    cause: e.message
  })
end
