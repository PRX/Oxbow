require "aws-sdk-sts"
require "aws-sdk-s3"

class String
  def underscore
    gsub("::", "/")
      .gsub(/([A-Z]+)([A-Z][a-z])/, '\1_\2')
      .gsub(/([a-z\d])([A-Z])/, '\1_\2')
      .tr("-", "_")
      .downcase
  end
end

# The Ruby AWS SDK does not intelligently handle cases where the client isn't
# explicitly set for the region where the bucket exists. We have to detect
# the region using HeadBucket, and then create the client with the returned
# region.
# TODO This isn't necessary when the bucket and the client are in the same
# region. It would be possible to catch the error and do the lookup only when
# necessary.
def bucket_region(credentials, destination)
  @bucket_regions ||= {}

  # Create a client with permission to HeadBucket
  @bucket_regions[destination["BucketName"]] ||= begin
    s3_writer = Aws::S3::Client.new(credentials: credentials, endpoint: "https://s3.amazonaws.com")
    bucket_head = s3_writer.head_bucket({bucket: destination["BucketName"]})
    bucket_head.context.http_response.headers["x-amz-bucket-region"]
  rescue Aws::S3::Errors::Http301Error, Aws::S3::Errors::PermanentRedirect => e
    e.context.http_response.headers["x-amz-bucket-region"]
  end
end

def s3_client(destination)
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

  region = bucket_region(credentials, destination)

  # Create a new client with the permissions and the correct region
  Aws::S3::Client.new(credentials: credentials, region: region)
end

def send_to_s3(output, local_file_name)
  destination = output["Destination"]
  return unless destination["Mode"] == "AWS/S3"

  s3_writer = s3_client(destination)
  put_object_params = {}

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
  puts JSON.dump({
    msg: "Sending output file to S3",
    format: output["Format"],
    opts: output["Options"],
    region: bucket_region,
    bucket: destination["BucketName"],
    object: destination["ObjectKey"]
  })
  put_ouput_s3tm = Aws::S3::TransferManager.new(client: s3_writer)
  put_ouput_s3tm.upload_file(local_file_name, **put_object_params)
end

def wip_to_s3(output, str)
  destination = output["Destination"]
  return unless destination["Mode"] == "AWS/S3"

  client = s3_client(destination)
  bucket = destination["BucketName"]
  key = destination["ObjectKey"] + ".wip"
  client.put_object(body: str, bucket: bucket, key: key)
end
