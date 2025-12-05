#!/usr/bin/env ruby

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

require "json"
require "time"
require "open3"
require "aws-sdk-states"
load "./telemetry.rb"
load "./destinations.rb"

sf = Aws::States::Client.new

begin
  puts JSON.dump({msg: "Starting task…"})
  send_start_metric

  task_result = {
    Task: ENV["STATE_MACHINE_TASK_TYPE"],
    FFmpeg: {
      Outputs: []
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

  # Execute the command
  ffmpeg_outputs = outputs.each_with_index.map { |o, idx| "#{o["Options"]} -f #{o["Format"]} output-#{idx}.file" }.join(" ")
  ffmpeg_cmd = [
    "ffmpeg",
    ffmpeg_global_opts,
    ffmpeg_inputs.to_s,
    ffmpeg_outputs.to_s
  ].join(" ")

  puts JSON.dump({
    msg: "Running FFmpeg",
    global_opts: ffmpeg_global_opts,
    input_opts: ffmpeg_inputs.to_s,
    outputs_opts: ffmpeg_outputs.to_s,
    full_command: ffmpeg_cmd
  })

  raise StandardError, "FFmpeg failed" unless system ffmpeg_cmd

  end_time = Time.now.to_i
  duration = end_time - start_time

  puts JSON.dump({msg: "FFmpeg exited successfully in #{duration} seconds"})

  outputs.each_with_index do |output, idx|
    puts JSON.dump({msg: "Running FFprobe for output file", format: output["Format"], opts: output["Options"]})

    # Probe the outputs of the command
    ffprobe_cmd = [
      "ffprobe",
      "-v error",
      "-show_streams",
      "-show_format",
      "-i output-#{idx}.file",
      "-print_format json"
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
      send_to_s3(output, destination, "output-#{idx}.file")
    end
  end

  now = Time.now
  task_result["Time"] = now.getutc.iso8601
  task_result["Timestamp"] = now.to_i

  puts JSON.dump({msg: "Task output", output: task_result})
  sf.send_task_success({
    task_token: ENV["STATE_MACHINE_TASK_TOKEN"],
    output: task_result.to_json
  })

  send_end_metric(duration)
  puts JSON.dump({msg: "Task complete; success has been reported to state machine"})
rescue => e
  puts JSON.dump({msg: "Task failed!", error: e.class.name, cause: e.message})
  sf.send_task_failure({
    task_token: ENV["STATE_MACHINE_TASK_TOKEN"],
    error: e.class.name,
    cause: e.message
  })
end
