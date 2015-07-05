# Taskflow

Taskflow is a cool rails plugin for creating and schedule task flows. NOTE: taskflow is based sidekiq, and use ActiveRecord/Mongoid as its database adapter, choose the right gem(another version taskflow is also in my github) for your project.

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'taskflow-mongoid',:require=>'taskflow'
```

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install taskflow-mongoid

## Usage

Let's see an example first, the 'PlayFlow' has 7 task in total. When we start the flow, the t1(PendingTask) runs first, after t1 finishes, t2,t3,t4 would run in parallel; When t4 is done, the t5(OkTask) begins, when t2,t3,t5 are all done, the SummaryTask start to run, then run the last OkTask.

```ruby
class PlayFlow < Taskflow::Flow
    NAME = "Play FLow"
    def configure
        t1 = run PendingTask, params: input, name: 'pending-task'
        t2 = run OkTask,after: t1,name: 'ok-task'
        t3 = run AlwaysFailTask,after: t1,name: 'always-fail-task'
        t4 = run RetryPassTask,after: t1,name: 'retry-pass-task'
        t5 = run OkTask,after: t4,name: 'just-play-task'
        run SummaryTask,after: [t2,t3,t5],name: 'summary-task'
        run OkTask,params: {love: 3},name: 'finished-task'
    end
end
class PendingTask < Taskflow::Task
    def go(logger)
        logger.info "I got input paramter: #{input}"
        logger.info 'first step,then suspend'
        if data[:who]
            logger.info "cool, #{data[:who]} wake me up!"
            tflogger.info 'Pending task wake up'
            set_output :reason=>'you are cool'
        else
            logger.info 'I would suspended now, wake for your wakeup.'
            suspend
        end
    end
end
class OkTask < Taskflow::Task
    def go(logger)
        set_output "result"=>(rand 10)
        logger.info "#{self.name} finished"
    end
end
class AlwaysFailTask < Taskflow::Task
    def go(logger)
        logger.info 'I would always fail, pls skip me'
        raise 'Ops, always fail!!!'
    end
end
class SummaryTask < Taskflow::Task
    def go(logger)
        logger.info 'get upstream output'
        upstream.each do |task|
            logger.info "Upstream task[#{task.name}]: #{task.output}"
        end
    end
end

class RetryPassTask < Taskflow::Task
    def go(logger)
        if data.empty?
            set_data :success_next_time=>true
            raise 'fail, please retry'
        else
            logger.info 'second time ok'
        end
        logger.info 'retry succeed'
    end
end
```
Then schedule taskflow like below:

```ruby
f=Taskflow::Flow.launch 'PlayFlow',:params=>{word: 'hello'},:launched_by=>'Jason',:workflow_description=>'desc'
# find PendingTask
t=f.tasks.where(state: 'paused',result: 'suspend').first
t.wakeup :who=>'Tom'
# find AlwaysFailTask
t=f.tasks.find_by name: 'always-fail-task'
puts t.error
# {"class"=>"RuntimeError", "message"=>"Ops, always fail!!!", "backtrace"=>["/U..."]}
t.skip
t=f.tasks.find_by name: 'retry-pass-task'
t.resume
# wait for while
puts f.state # => stopped
# and we can check the log of taskflow itself
puts f.logger.records

# all sidekiq log
Taskflow::Worker JID-905f46ac2a14b79329cc2526 INFO: start
Taskflow::Worker JID-905f46ac2a14b79329cc2526 INFO: I got input paramter: {"word"=>"hello"}
Taskflow::Worker JID-905f46ac2a14b79329cc2526 INFO: first step,then suspend
Taskflow::Worker JID-905f46ac2a14b79329cc2526 INFO: I would suspended now, wake for your wakeup.
Taskflow::Worker JID-905f46ac2a14b79329cc2526 INFO: done: 0.034 sec
Taskflow::Worker JID-cdcba34bc5f4746d0f0b68ad INFO: start
Taskflow::Worker JID-cdcba34bc5f4746d0f0b68ad INFO: I got input paramter: {"word"=>"hello"}
Taskflow::Worker JID-cdcba34bc5f4746d0f0b68ad INFO: first step,then suspend
Taskflow::Worker JID-cdcba34bc5f4746d0f0b68ad INFO: cool, Tom wake me up!
Taskflow::Worker JID-cdcba34bc5f4746d0f0b68ad INFO: done: 0.059 sec
Taskflow::Worker JID-2167fefe864f5de18ca7341e INFO: start
Taskflow::Worker JID-f1131d60a2d7530953f346ec INFO: start
Taskflow::Worker JID-259ef2694a65e235cf010b1e INFO: start
Taskflow::Worker JID-259ef2694a65e235cf010b1e INFO: I would always fail, pls skip me
Taskflow::Worker JID-2167fefe864f5de18ca7341e INFO: ok-task finished
Taskflow::Worker JID-259ef2694a65e235cf010b1e INFO: done: 0.077 sec
Taskflow::Worker JID-2167fefe864f5de18ca7341e INFO: done: 0.083 sec
Taskflow::Worker JID-f1131d60a2d7530953f346ec INFO: done: 0.084 sec
Taskflow::Worker JID-2d4f24491b84a68334cebaab INFO: start
Taskflow::Worker JID-2d4f24491b84a68334cebaab INFO: done: 0.022 sec
Taskflow::Worker JID-6312d5b0e1c66602bf04372e INFO: start
Taskflow::Worker JID-6312d5b0e1c66602bf04372e INFO: second time ok
Taskflow::Worker JID-6312d5b0e1c66602bf04372e INFO: retry succeed
Taskflow::Worker JID-6312d5b0e1c66602bf04372e INFO: done: 0.027 sec
Taskflow::Worker JID-dda69c567c7009219f6237b6 INFO: start
Taskflow::Worker JID-dda69c567c7009219f6237b6 INFO: just-play-task finished
Taskflow::Worker JID-dda69c567c7009219f6237b6 INFO: done: 0.032 sec
Taskflow::Worker JID-7163d1fa16a685d016642a6b INFO: start
Taskflow::Worker JID-7163d1fa16a685d016642a6b INFO: get upstream output
Taskflow::Worker JID-7163d1fa16a685d016642a6b INFO: Upstream task[ok-task]: {"result"=>4}
Taskflow::Worker JID-7163d1fa16a685d016642a6b INFO: Upstream task[always-fail-task]: {}
Taskflow::Worker JID-7163d1fa16a685d016642a6b INFO: Upstream task[just-play-task]: {"result"=>0}
Taskflow::Worker JID-7163d1fa16a685d016642a6b INFO: done: 0.03 sec
Taskflow::Worker JID-d7d0c92da5ab820bc1f66651 INFO: start
Taskflow::Worker JID-d7d0c92da5ab820bc1f66651 INFO: finished-task finished
Taskflow::Worker JID-d7d0c92da5ab820bc1f66651 INFO: done: 0.021 sec
```


## Documentations
### the Taskflow::Flow
First, you should create your taskflow by inherit `Taskflow::Flow`, and you *must implement the `configure` method* to tell taskflow engine the detail info.

In `configure` method, you can use the keyword `run` to define task:

```ruby
# the keyword run
run Task_Class, name: 'task_name'
# task1 would run before another_task_obj
run Task_Class, name: 'task1',:before=>another_task_obj
# task2 would run after another_task_obj
run Task_Class, name: 'task2',:after=>another_task_obj
# the wait_task would run after task3,task4,task5 all done
run Task_Class, name: 'wait_task',:after=>[task3,task4,task5]
# pass some parameter to task, the params would set as task's input
run Task_Class, name: 'params_task',params: { :param1=>'abc' }
```

You can use `after` or `before` to specify the schedule order for certain task, if there's no after or before, the current task would just run after the previous task.

#### 1. launch taskflow
```ruby
# the params would be set as taskflow's input field
Taskflow::Flow.launch 'PlayFlow',:params=>{word: 'hello'},:launched_by=>'Jason',:workflow_description=>'description'
# check whether can launch taskflow, if there's already a taskflow which has the some taskflow_klass and params, return false
Taskflow::Flow.can_launch? 'PlayFlow',:params=>{word: 'hello'},:launched_by=>'Jason',:workflow_description=>'description'
```

#### 2. taskflow control
```ruby
# Taskflow::Flow#stop! stop taskflow
flow.stop!
flow.stop! 'tom' # => stopped by tom
# Taskflow::Flow#resume, resume paused flow
flow.resume
```

### the Taskflow::Task
Define your own taskflow task. Inherit the class `Taskflow::Task`, and *implement go method*.

```ruby
def go(logger)
# write your task code here
end
```

#### 1.Sidekiq logger
the parameter `logger` of `Taskflow::Task#go` is sidekiq logger, so you can use it to log to sidekiq log file for debug.

#### 2.taskflow logger
There's another logger in `Taskflow::Task#go` : `tflogger`, `tflogger` can write log information to database. for example:

```ruby
def go(logger)
  tflogger.info 'the info message would write to database'
  tflogger.error 'this error message would write to database,too'
end
```

#### 3. input & output
There's a very cool feature. Every task has its own `input` and `ouput`.
```ruby
def go(logger)
  puts input # => the input hash
  puts input[:some_key] # => get the input value of the key 'some_key'
  puts upstream.first.ouput # => get the first upstream's ouput, also is a hash
end
```

You have the `set/append_xxx` to modify the input and output.
```ruby
def go(log)
  set_output :some_key=>'value' # => set the output to { :some_key=> 'value'}
  append_output :some_key2=>'value2' # => add { :some_key2=>'value2' } to output
end
```

#### 4. data
Every task has its own data. After the task is done, the data would be cleanned.
```ruby
def go(log)
  puts data # => print data
  puts data[:key] # => access data
  set_data :key=>'value'
  append_data :key=>'value'
end
```

#### 5. relationship
In the task, you can access its upstream and downstream.
```ruby
def go(log)
  upstream.each{|task| puts task.name }
  upstream.each{|task| puts task.output }
  puts downstream.first.name
end
```

#### 6. task control
```ruby
task.resume # => resume paused task
task.wakeup(hash_data) # => wakeup suspend task with some hash data
task.wakeup # => just wakeup
task.skip # => skip paused task
```
And, in `Taskflow::Task#go`, you can use keyword `suspend` to suspend current task, then the task result would convert to `suspend`,state would be `paused`.
```ruby
def go(log)
  log.info 'before suspend'
  suspend  # => the task would be suspend right now.
  log.info 'never print me'
end
```

## Development

After checking out the repo, run `bin/setup` to install dependencies. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and tags, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/[USERNAME]/taskflow. This project is intended to be a safe, welcoming space for collaboration, and contributors are expected to adhere to the [Contributor Covenant](contributor-covenant.org) code of conduct.


## License

The gem is available as open source under the terms of the [MIT License](http://opensource.org/licenses/MIT).

