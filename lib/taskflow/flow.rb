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

    # opts support :name,:params
    def run(klass,opts={})
        obj = {
            klass: klass.to_s,
            name: opts[:name] || klass.to_s,
            input: opts[:params],
            index: self.tasks.size + 1
        }
        task = klass.create obj.select{|k,v| v }
        if opts[:before]
            task.downstream << opts[:before]
        end
        if opts[:after]
            task.upstream << opts[:after]
        end
        if opts[:before].nil? && opts[:after].nil? && self.tasks.last
            self.tasks.last.downstream << task
        end
        self.tasks << task
        task
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
            configure
            sort_index  1,[]
        rescue=>exception
            self.destroy
            raise exception
        end
        reload
    end

    def sort_index(i,scanned)
        queue = self.tasks.nin(id: scanned).select{|t| t.upstream.empty? || t.upstream.all?{|upt| scanned.include?(upt.id.to_s)}}
        return if queue.empty?
        queue.each do |task|
            task.update_attributes index: i
            scanned << task.id.to_s
        end
        sort_index i + 1,scanned
    end
end
