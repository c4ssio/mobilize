module Mobilize
  class AwsPath
    include Mongoid::Document
    include Mongoid::Timestamps
    field :url, type: String #uniquely identifies dst and handler
  end
end
