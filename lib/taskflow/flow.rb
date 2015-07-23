# coding: utf-8
class Taskflow::Flow
    include ::Mongoid::Document

    field :name, type: String
    field :klass, type: String, default: -> { self.class.to_s }
    field :state, type: String, default: 'pending'
    field :category, type: String, default: 'simple'
    field :result, type: String
    field :launched_by, type: String
    field :halt_by, type: String
    field :input,type: Hash
    field :progress,type: Float, default: 0
    field :started_at, type: Time
    field :ended_at, type: Time
    field :next_config, type: Hash

    after_create :configure_tasks

    has_many :tasks, :class_name=>'Taskflow::Task',:inverse_of=>:flow,:dependent => :destroy
    has_one :logger,:class_name=>'Taskflow::Logger',:inverse_of=>:flow, :dependent => :destroy

    class << self

        # opts support :params,
        def can_launch?(klass,opts={})
            opts = HashWithIndifferentAccess.new opts
            !Taskflow::Flow.ne(state: 'stopped').where(klass: klass,input: opts[:params]).exists?
        end

        def launch(klass,opts={})
            opts = HashWithIndifferentAccess.new opts
            flow_klass = Kernel.const_get klass
            name = flow_klass.const_get 'NAME'
            opts[:launched_by] ||= 'task-flow-engine'
            flow = flow_klass.create name: name,input: opts[:params],launched_by: opts[:launched_by]
            if opts[:next_workflow_config]
                flow.update next_config: opts[:next_workflow_config]
            end
            flow.create_logger name: name,description: opts[:workflow_description]
            flow.schedule
        end
    end

    def running_steps
        self.tasks.in(state: ['running','paused'])
    end

    def stop!(user_id=nil)
        percent = self.tasks.map(&:progress).sum / self.tasks.size
        self.update_attributes! progress: percent,halt_by: user_id,ended_at: Time.now, state: 'stopped',result: 'warning'
    end

    def resume
        self.tasks.where(state: 'paused',result: 'error').each do |task|
            task.resume
        end
    end

    def schedule
        return if self.halt_by || self.state == 'stopped'
        self.update_attributes! state: 'running',started_at: Time.now if self.state == 'pending'
        task_list = []
        self.reload.tasks.where(state: 'pending').each do |task|
            # 上游全部完成
            if task.upstream.empty? || task.upstream.all?{|t| %w(skipped stopped).include? t.state }
                task_list << task.id.to_s
            end
        end
        task_list.each{|tid| Taskflow::Worker.perform_async self.id.to_s,tid }
        self
    end

    private

    def configure_tasks
        begin
            @task_list = []
            configure
            sort_index  1,[]
            TaskFlow::Task.collection.insert @task_list
            @task_list = nil
        rescue=>exception
            self.destroy
            raise exception
        end
        reload
    end

    # opts support :name,:params
    def run(klass,opts={})
        task_data = {
            klass: klass.to_s,
            name: opts[:name] || klass.to_s,
            input: opts[:params],
            index: @task_list.size + 1,
            _type: klass.to_s,
            state: 'pending',
            output: {},
            input: {},
            progress: 0,
            data: {},
            flow_id: self.id,
            _id: BSON::ObjectId.new,
            downstream_ids: [],
            upstream_ids: []
        }.select{|k,v| v }
        if opts[:before]
            if opts[:before].is_a? Array
                opts[:before].flatten!
                opts[:before].each do |b|
                    b[:upstream_ids] << task_data[:_id]
                    task_data[:downstream_ids]  << b[:_id]
                end
            else
                task_data[:downstream_ids]  << opts[:before][:_id]
                opts[:before][:upstream_ids] << task_data[:_id]
            end
        end
        if opts[:after]
            if opts[:after].is_a? Array
                opts[:after].flatten!
                opts[:after].each do |a|
                    task_data[:upstream_ids]  << a[:_id]
                    a[:downstream_ids] << task_data[:_id]
                end
            else
                task_data[:upstream_ids]  << opts[:after][:_id]
                opts[:after][:downstream_ids] << task_data[:id]
            end
        end
        if opts[:before].nil? && opts[:after].nil? && @task_list.last
            @task_list.last[:downstream_ids]  << task_data
            task_data[:upstream_ids] << @task_list.last[:_id]
        end
        @task_list << task_data
        task_data
    end

    def sort_index(i,scanned)
        queue = @task_list.select{|t| !scanned.include?(t[:_id]) && (t[:upstream_ids].nil? || t[:upstream_ids].empty? || t[:upstream_ids].all?{|uid| scanned.include?(uid)}) }
        return if queue.empty?
        queue.each do |task|
            task[:index] = i
            scanned << task[:_id]
        end
        sort_index i + 1,scanned
    end
end
