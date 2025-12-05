# Oxbow

Oxbow is a general-purpose job processor. It is designed to work asynchronously – jobs are sent to Oxbow from other applications, and the results can be returned to the applications via callbacks. It is a close relative to [Porter](https://github.com/prx/Porter), and general shares architecture and API.

See the Porter [README](https://github.com/PRX/Porter/blob/main/README.md) for detailed information about I/O, permissions, etc. Oxbow does not currently have feature parity with Porter in all cases.

## Tasks

### FFmpeg

Each `FFmpeg` task runs an arbitrary FFmpeg command.

`FFmpeg.Inputs` is expected to exist, and contain all input parameters for the command as a single string. The input is generally expected to be a source that is accessible over the public internet.

`FFmpeg.GlobalOptions` is optional, and can contain all global parameters as a single string.

`FFmpeg.Outputs` is expected to exist and is an array. Each element in the array represents an output of the FFmpeg command, and details on where that output should be stored. Within each element: `Format` is required and indicates how the output should be encoded. `Options` is required and is a string that contains a single set of output parameters **without the file name**. For example, if you normally would have included `-b:a 128k output.mp3` in the command, `Options` should include `-b:a 128k`. `Destination` is expected to exist and currently supports the `AWS/S3` mode. You should ensure that the file extensions, content-types, etc that you define match the results of the output options; Oxbow will not make any inferences about file types.

Input:

```json
{
    "Type": "FFmpeg",
    "FFmpeg": {
        "Inputs": "-t 60 -i \"http://example.com/stream.m3u8\"",
        "GlobalOptions": "-loglevel debug",
        "Outputs": [
            {
                "Format": "flac",
                "Options": "-sample_fmt s16 -ar 48000",
                "Destination": {
                    "Mode": "AWS/S3",
                    "BucketName": "myBucket",
                    "ObjectKey": "myObject.flac",
                    "Parameters": {
                        "CacheControl": "max-age=604800",
                        "ContentDisposition": "attachment; filename=\"download.flac\"",
                        "ContentType": "audio/flac"
                    }
                }
            },
            {
                "Format": "mp3",
                "Options": "-b:a 128k",
                "Destination": {
                    "Mode": "AWS/S3",
                    "BucketName": "myBucket",
                    "ObjectKey": "myObject.mp3",
                    "Parameters": {
                        "CacheControl": "max-age=604800",
                        "ContentDisposition": "attachment; filename=\"download.mp3\"",
                        "ContentType": "audio/flac"
                    }
                }
            }
        ]
    }
}
```
You could also generate files with no external input:

```json
{
    "Type": "FFmpeg",
    "FFmpeg": {
        "Inputs": "-f lavfi -i sine=frequency=440:beep_factor=4:sample_rate=48000:duration=10",
        "GlobalOptions": "-loglevel warning",
        "Outputs": [
            {
                "Format": "wav",
                "Options": "-ac 2 -codec:a pcm_s16le",
                "Destination": {
                    "Mode": "AWS/S3",
                    "BucketName": "myBucket",
                    "ObjectKey": "myObject.wav",
                    "Parameters": {
                        "CacheControl": "max-age=604800",
                        "ContentDisposition": "attachment; filename=\"download.wav\"",
                        "ContentType": "audio/wav"
                    }
                }
            },
            {
                "Format": "mp3",
                "Options": "-ac 2 -codec:a libmp3lame",
                "Destination": {
                    "Mode": "AWS/S3",
                    "BucketName": "myBucket",
                    "ObjectKey": "myObject.wav",
                    "Parameters": {
                        "CacheControl": "max-age=604800",
                        "ContentDisposition": "attachment; filename=\"download.mp3\"",
                        "ContentType": "audio/mpeg"
                    }
                }
            }
        ]
    }
}
```
