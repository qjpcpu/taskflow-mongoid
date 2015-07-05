class Taskflow::Record
    include ::Mongoid::Document
    embedded_in :logger,:class_name=>'Taskflow::Logger',:inverse_of=>:records

    field :step_id, type: Integer
    field :writer, type: String
    field :written_at, type: Time, default: ->{ Time.now }
    field :level, type: String, default:  'INFO'
    field :content, type: String
    field :tags, type: Hash, default: {}
end
