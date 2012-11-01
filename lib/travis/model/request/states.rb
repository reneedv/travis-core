require 'active_support/concern'
require 'simple_states'

class Request
  module States
    extend ActiveSupport::Concern
    include SimpleStates, Travis::Event

    included do
      states :created, :started, :finished
      event :start,     :to => :started, :after => :configure
      event :configure, :to => :configured, :after => :finish
      event :finish,    :to => :finished
      event :all, :after => :notify
    end

    def configure
      if !accepted?
        Travis.logger.warn("[request:configure] Request not accepted: event_type=#{event_type.inspect} commit=#{commit.commit.inspect} message=#{approval.message.inspect}")
      elsif config.present?
        Travis.logger.warn("[request:configure] Request not configured: config not blank, config=#{config.inspect} commit=#{commit.commit.inspect}")
      else
        self.config = fetch_config
        Travis.logger.info("[request:configure] Request successfully configured commit=#{commit.commit.inspect}")
      end
    end

    def finish
      if config.blank?
        Travis.logger.warn("[request:finish] Request not creating a build: config is blank, config=#{config.inspect} commit=#{commit.commit.inspect}")
      elsif !approved?
        Travis.logger.warn("[request:finish] Request not creating a build: not approved commit=#{commit.commit.inspect} message=#{approval.message.inspect}")
      else
        add_build
        Travis.logger.info("[request:finish] Request created a build. commit=#{commit.commit.inspect}")
      end
      self.result = approval.result
      self.message = approval.message
      Travis.logger.info("[request:finish] Request finished. result=#{result.inspect} message=#{message.inspect} commit=#{commit.commit.inspect}")
    end

    def requeueable?
      # finished? && !!builds.all { |build| build.finished? }
      !!builds.all { |build| build.finished? }
    end

    protected

      delegate :accepted?, :approved?, :to => :approval

      def approval
        @approval ||= Approval.new(self)
      end

      def fetch_config
        Travis::Services::Github::FetchConfig.new(self).run
      end

      def add_build
        builds.build(:repository => repository, :commit => commit, :config => config, :owner => owner)
      end
  end
end
