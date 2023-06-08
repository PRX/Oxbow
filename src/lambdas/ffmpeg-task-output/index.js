// Because the result of a Fargate task is not sufficient for sending a proper
// callback, this function takes the entire task input and builds a better
// result that gets passed to the callback task.

const AWS = require("aws-sdk");

const s3 = new AWS.S3({ apiVersion: "2006-03-01" });

exports.handler = async (event) => {
  console.log(JSON.stringify({ msg: "State input", input: event }));

  const result = {
    Task: event.Task.Type,
    FFmpeg: {
      Outputs: [],
    },
  };

  for (let idx = 0; idx < event.Task.FFmpeg.Outputs.length; idx += 1) {
    // Get ffprobe results
    // eslint-disable-next-line no-await-in-loop
    const file = await s3
      .getObject({
        Bucket: process.env.ARTIFACT_BUCKET_NAME,
        Key: `${event.Execution.Id}/ffmpeg/ffprobe-${event.TaskIteratorIndex}-${idx}.json`,
      })
      .promise();
    const ffprobe = JSON.parse(file.Body.toString());

    result.FFmpeg.Outputs.push({
      Mode: event.Task.FFmpeg.Outputs[idx].Destination.Mode,
      BucketName: event.Task.FFmpeg.Outputs[idx].Destination.BucketName,
      ObjectKey: event.Task.FFmpeg.Outputs[idx].Destination.ObjectKey,
      Duration: +ffprobe.format.duration * 1000,
      Size: +ffprobe.format.size,
    });
  }

  const now = new Date();

  result.Time = now.toISOString();
  result.Timestamp = +now / 1000;

  console.log(JSON.stringify({ msg: "Result", result }));

  return result;
};
