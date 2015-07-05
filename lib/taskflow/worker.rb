# coding: utf-8
class Taskflow::Worker
    include ::Sidekiq::Worker
    sidekiq_options :retry => false

    def perform(task_flow_id,job_id,opts={})
        flow = Taskflow::Flow.find task_flow_id
        task = Taskflow::Task.find job_id
        begin
            reason = catch :control do
                check_flow_state flow
                check_task_state task
                task.update_attributes! state: 'running',started_at: Time.now,ended_at: nil, progress: 0.5,output: {},error: nil,result: nil
                task.go logger
            end
            case reason
            when :flow_halt
                flow.update_attributes! ended_at: Time.now unless flow.ended_at
            when :suspend
                task.update_attributes! result: 'suspend',state: 'paused'
            when :skip
                task.update_attributes! state: 'skipped',data: {}
            when :already_running,:already_stopped
                return
            else
                task.update_attributes! data: {},ended_at: Time.now,progress: 1,state: 'stopped',result: 'success'
            end
        rescue=>exception
            task.error = {
                class: exception.class.to_s,
                        message: exception.to_s,
                        backtrace: exception.backtrace
                    }
                    task.state = 'paused'
                    task.result = 'error'
                    task.ended_at = Time.now
                    task.save
                end
                update_flow flow.reload
                flow.schedule
                end

                private
                def check_flow_state(flow)
                    if flow.state == 'stopped' || flow.halt_by
                        throw :control, :flow_halt
                    end
                end
                def check_task_state(task)
                    case task.state
                    when 'pending'
                        task.update_attributes state: 'running'
                    when 'running'
                        throw :control, :already_running
                    when 'paused'
                        throw :control, :suspend if task.result == 'suspend'
                    when 'stopped'
                        throw :control, :already_stopped
                    when 'skipped'
                        throw :control,:skip
                    else
                        raise "Unkown task state #{task.state}"
                    end
                end

                def update_flow(flow)
                    return if flow.halt_by || flow.state == 'stopped'
                    flow.progress = flow.tasks.map(&:progress).sum / flow.tasks.size
                    if flow.halt_by
                        flow.state = 'stopped'
                    elsif flow.tasks.all?{|t| %w(stopped skipped).include? t.state }
                        flow.state = 'stopped'
                    elsif flow.tasks.any?{|t| t.state == 'paused' }
                        flow.state = 'paused'
                        flow.result = flow.tasks.find_by(state: 'paused').result
                    else
                        flow.state = 'running'
                    end
                    if flow.state == 'stopped'
                        flow.result = flow.tasks.all?{|t| t.result == 'success' } ? 'success' : 'warning'
                        flow.ended_at = Time.now
                        if flow.next_config
                            logger.info "Auto boot next flow, #{flow.next_config}"
                            Taskflow::Flow.launch flow.next_config[:name],flow.next_config[:config]
                        end
                    end
                    flow.save
                end

                end
