# coding: utf-8
class Taskflow::Task
    include ::Mongoid::Document

    field :index, type: Integer, default: 1
    field :name, type: String
    field :klass, type: String, default: -> { self.class.to_s }
    # all aviable states: :pending, :running, :paused, :stopped, :skipped
    field :state, type: String, default: 'pending'
    field :result,type: String

    field :started_at, type: Time
    field :ended_at, type: Time

    field :output,type: Hash, default: {}
    # task flow params would be set here
    field :input,type: Hash, default: {}
    field :error, type: Hash

    field :progress, type: Float, default: 0

    # tmp data, would be wipe out after task finished
    field :data, type: Hash, default: {}

    # do not save myself in up or downstream
    before_save :remove_self_in_stream

    has_and_belongs_to_many :downstream, :class_name=>'Taskflow::Task',:inverse_of=>:upstream
    has_and_belongs_to_many :upstream, :class_name=>'Taskflow::Task',:inverse_of=>:downstream

    belongs_to :flow,:class_name=>'Taskflow::Flow',:inverse_of=>:tasks

    def go(sidekiq_logger)
    end

    def resume
        if self.state == 'paused' && self.result == 'error'
            self.flow.update_attributes! state: 'running'
            Taskflow::Worker.perform_async self.flow.id.to_s,self.id.to_s
        end
    end

    def wakeup(arguments={})
        self.reload
        if self.state == 'paused' && self.result == 'suspend'
            self.data = self.data.merge arguments
            self.result = nil
            self.save
            Taskflow::Worker.perform_async self.flow.id.to_s,self.id.to_s
        end
    end

    def skip
        self.reload
        if self.state == 'paused'
            self.update_attributes! state: 'skipped'
            Taskflow::Worker.perform_async self.flow.id.to_s,self.id.to_s
        end
    end

    private

    def remove_self_in_stream
        downstream.delete self if downstream.include? self
        upstream.delete self if upstream.include? self
    end

    def suspend
        throw :control,:suspend
    end

    def tflogger
        @tflogger ||= (
            _logger = flow.logger
            _logger.instance_variable_set '@step_id',self.index
            _logger.instance_variable_set '@writer',self.name
            _logger
        )
    end

    def method_missing(name,*args)
        if /^(set|append|clear)_(input|output|data)$/ =~ name.to_s
            act,fd = name.to_s.split '_'
            if act == 'set'
                return false unless args.first
                self.update_attributes! "#{fd}"=>args.first
            elsif act == 'append'
                return false unless args.first
                self.update_attributes! "#{fd}"=>self.send("#{fd}").merge(args.first)
            else
                self.update_attributes! "#{fd}"=>{}
            end
        else
            super
        end
    end

end
