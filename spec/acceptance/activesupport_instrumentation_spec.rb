require "spec_helper"

unless ActiveSupport::Notifications.respond_to?(:subscribed)
  module SubscribedBehavior
    def subscribed(callback, *args, &block)
      subscriber = subscribe(*args, &callback)
      yield
    ensure
      unsubscribe(subscriber)
    end
  end

  ActiveSupport::Notifications.extend SubscribedBehavior
end

describe "using ActiveSupport::Instrumentation to track factory interaction" do
  let(:slow_user_factory) { FactoryGirl.factory_by_name("slow_user") }
  let(:user_factory) { FactoryGirl.factory_by_name("user") }
  before do
    define_model("User", email: :string)
    FactoryGirl.define do
      factory :user do
        email "john@example.com"

        factory :slow_user do
          after(:build) { Kernel.sleep(0.1) }
        end
      end

    end
  end

  it "tracks proper time of creating the record" do
    time_to_execute = 0
    callback = ->(name, start, finish, id, payload) { time_to_execute = finish - start }
    ActiveSupport::Notifications.subscribed(callback, "factory_girl.run_factory") do
      FactoryGirl.build(:slow_user)
    end

    expect(time_to_execute).to be >= 0.1
  end

  it "builds the correct payload" do
    tracked_invocations = {}

    callback = ->(name, start, finish, id, payload) do
      factory_name = payload[:name]
      strategy_name = payload[:strategy]
      factory = payload[:factory]
      tracked_invocations[factory_name] ||= {}
      tracked_invocations[factory_name][strategy_name] ||= 0
      tracked_invocations[factory_name][strategy_name] += 1
      tracked_invocations[factory_name][:factory] = factory
    end

    ActiveSupport::Notifications.subscribed(callback, "factory_girl.run_factory") do
      FactoryGirl.build_list(:slow_user, 2)
      FactoryGirl.build_list(:user, 5)
      FactoryGirl.create_list(:user, 2)
      FactoryGirl.attributes_for(:slow_user)
    end

    expect(tracked_invocations[:slow_user][:build]).to eq(2)
    expect(tracked_invocations[:slow_user][:attributes_for]).to eq(1)
    expect(tracked_invocations[:slow_user][:factory]).to eq(slow_user_factory)
    expect(tracked_invocations[:user][:build]).to eq(5)
    expect(tracked_invocations[:user][:factory]).to eq(user_factory)
  end
end
