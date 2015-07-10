require "taskflow/version"
require 'active_support/core_ext/hash/indifferent_access'
require 'taskflow/flow'
require 'taskflow/task'
require 'taskflow/worker'
require 'taskflow/logger'
require 'taskflow/record'

module Taskflow

    DEFAULTS = { :retry=>false }

    def self.worker_options
        @options ||= DEFAULTS.dup
    end

    def self.worker_options=(opts)
        @options = opts.merge DEFAULTS.dup
    end
    
    def self.configure
        yield self
    end
end
