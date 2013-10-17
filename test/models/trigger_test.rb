require "test_helper"
class TriggerTest < MiniTest::Unit::TestCase
  def setup
    Mongoid.purge!
    Mobilize::Job.purge!
    @worker_name               = Mobilize.config.fixture.box.worker_name
    @box                       = Mobilize::Fixture::Box.default     @worker_name
    @box_session               = Mobilize::Box.session
    @box.find_or_create_instance @box_session
    @user                      = Mobilize::Fixture::User.default
    @job                       = Mobilize::Fixture::Job.default     @user, @box
    @parent_job                = Mobilize::Fixture::Job.parent      @user, @box
  end

  def test_tripped
    @class_methods             = Mobilize::Fixture::Trigger.methods false
    @trip_methods              = @class_methods.select{|m| m.to_s.starts_with?("_")}
    @trip_methods.each        { |trip_method|
      if                         trip_method.to_s.index("parent")
        @parent_job.delete
        @parent_job            = Mobilize::Fixture::Job.parent @user, @box
        @job.delete
        @job                   = Mobilize::Fixture::Job.default @user, @box
        @expected              = Mobilize::Fixture::Trigger.send(trip_method, @job, @parent_job)
      else
        @job.delete
        @job                   = Mobilize::Fixture::Job.default @user, @box
        @expected              = Mobilize::Fixture::Trigger.send(trip_method, @job)
      end
      Mobilize::Logger.info      "Checking Trigger #{trip_method.to_s}"
      assert_equal               @expected, @job.trigger.tripped?
                              }
  end

end
