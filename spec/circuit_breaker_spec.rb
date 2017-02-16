require "spec_helper"

describe CircuitBreaker do
  let(:circuit) do
    ->(arg) { service(arg) }
  end
  let(:breaker) do
    CircuitBreaker::Memory.new do |cb|
      cb.circuit = circuit
      cb.failure_limit = failure_limit
    end
  end
  it "has a version number" do
    expect(CircuitBreaker::VERSION).not_to be nil
  end
  context "#call" do
    it 'calls do_run with args and the circuit' do
      allow(breaker).to receive(:check_reset_timeout)
      allow(breaker).to receive(:open?).and_return(false)
      expect(breaker).to receive(:do_run).with([success], &circuit)
      breaker.call(success)
    end
    it 'raises an error if the breaker is open' do
      allow(breaker).to receive(:check_reset_timeout)
      allow(breaker).to receive(:open?).and_return(true)
      expect {
        breaker.call(failure)
      }.to raise_error(CircuitBreaker::OpenError)
    end
    it 'checks if the reset_timeout has lapsed and if so changes the state' do
      allow(breaker).to receive(:open?).and_return(true, false)
      allow(breaker).to receive(:reset_period_lapsed?).and_return(true)

      expect(breaker).to receive(:state=).with(:half_open)
      expect(breaker).to receive(:state=).with(:closed)
      breaker.call(success)
    end
  end
  context "#failure_count" do
    it 'returns an integer' do
      failures = 2
      failures.times { breaker.call(failure) }
      expect(breaker.failure_count).to eq failures
    end
  end
  [:open, :closed, :half_open].each do |state|
    context "##{state}?" do
      it 'returns a bool' do
        allow(breaker).to receive(:state).and_return(state)
        expect(breaker.send("#{state}?")).to eq true
      end
    end
  end
  context "class needs to implement" do
    let(:breaker) do
      Helpers::MyAdapter.new do |a|
        a.circuit = -> { }
      end
    end
    context 'getters' do
      [:failures, :state].each do |method|
        it "must implement #{method}" do
          expect {
            breaker.send(method)
          }.to raise_error(NotImplementedError)
        end
      end
    end
    context 'setters' do
      [:failures=, :add_failure, :state=].each do |method|
        it "must implement #{method}" do
          expect {
            breaker.send(method, "arg")
          }.to raise_error(NotImplementedError)
        end
      end
    end
    context "validations" do
      it 'requires logging level methods if using a custom logger' do
        breaker =  Helpers::MyAdapter.new do |cb|
          cb.circuit = -> { }
          cb.logger = double('bad logger')
        end
        expect {
          breaker.run_validations
        }.to raise_error(NotImplementedError, "Your logger must respond to [:debug, :info, :warn, :error]")
      end
      it 'requires the circuit be callable' do
        breaker = Helpers::MyAdapter.new { |cb| cb.circuit = :some_method }
        expect {
          breaker.run_validations
        }.to raise_error(NotImplementedError, "Your circuit must respond to #call")
      end
    end
  end

  # describe "intializer" do
  #   describe "defaults" do
  #     let(:breaker) do
  #       CircuitBreaker.new do |cb|
  #         cb.circuit = -> (arg) { service(arg) }
  #       end
  #     end
  #     it 'defaults to ruby logger' do
  #       expect(breaker.logger).to be_a Logger
  #     end
  #     it 'sets a reset timeout of 10 seconds' do
  #       expect(breaker.reset_timeout).to eq 10
  #     end
  #     it 'works with any number of arguments' do
  #       breaker = CircuitBreaker.new { |cb| cb.circuit = -> (a1, a2) { a1 + a2 } }
  #       expect { breaker.call(1,2) }.to_not raise_error
  #     end
  #     it "defaults to the memory adapter" do
  #       expect(breaker.adapter).to be_a CircuitBreaker::Adapters::Memory
  #     end
  #     describe "validations" do
  #       it 'requires logging level methods if using a custom logger' do
  #         expect {
  #           CircuitBreaker.new do |cb|
  #             cb.circuit = -> { }
  #             cb.logger = Helpers::DummyLogger
  #           end
  #         }.to raise_error(NotImplementedError, "Your logger must respond to [:debug, :info, :warn, :error]")
  #       end
  #       it 'requires the circuit be callable' do
  #         expect {
  #           CircuitBreaker.new { |cb| cb.circuit = :some_method }
  #         }.to raise_error(NotImplementedError, "Your circuit must respond to #call")
  #       end
  #     end
  #   end
  # end
  #
  # describe 'failed calls' do
  #   it "records failures" do
  #     breaker.call(failure)
  #     expect(breaker.failure_count).to eq 1
  #   end
  #
  #   it 'will not make calls and raise an error when failure limit is reached' do
  #     failure_limit.times { breaker.call(failure) }
  #
  #     expect(breaker.failure_count).to eq failure_limit
  #     expect(breaker.open?).to eq true
  #     expect { breaker.call(2) }.to raise_error(CircuitBreaker::Open)
  #   end
  # end
  #
  # describe 'resetting' do
  #   let(:breaker) do
  #     CircuitBreaker.new do |cb|
  #       cb.circuit = -> (arg) { service(arg) }
  #       cb.failure_limit = failure_limit
  #     end
  #   end
  #   it 'resets failures when successful' do
  #     # fail once
  #     breaker.call(failure)
  #     # succeed
  #     breaker.call(true)
  #
  #     expect(breaker.failure_count).to eq 0
  #     expect(breaker.open?).to eq false
  #   end
  #   it 'resets when a failure has passed reset_timeout' do
  #     # breaker will allow calls again after 0.5 second
  #     Timecop.freeze(Time.now)
  #     reset_timeout = 0.5
  #     breaker = CircuitBreaker.new do |cb|
  #       cb.circuit = -> (arg) { service(arg) }
  #       cb.failure_limit = failure_limit
  #       cb.reset_timeout = reset_timeout
  #     end
  #
  #     failure_limit.times { breaker.call(failure) }
  #     expect(breaker.open?).to eq true
  #     Timecop.travel(reset_timeout)
  #
  #     # try again without a failure
  #     breaker.call(success)
  #     expect(breaker.open?).to eq false
  #     expect(breaker.closed?).to eq true
  #     expect(breaker.failure_count).to eq 0
  #   end
  # end
  # describe 'state half open' do
  #   before(:each) do
  #     # breaker will allow calls again after 0.5 second
  #     Timecop.freeze(Time.now)
  #     reset_timeout = 0.5
  #     @breaker = CircuitBreaker.new do |cb|
  #       cb.circuit = -> (arg) { service(arg) }
  #       cb.failure_limit = failure_limit
  #       cb.reset_timeout = reset_timeout
  #     end
  #
  #     failure_limit.times { |i| @breaker.call(failure) }
  #     expect(@breaker.open?).to eq true
  #     Timecop.travel(reset_timeout)
  #   end
  #   it 'changes state to half open when reset_timeout is exceeded' do
  #     # we don't want to check the value of state before #reset_failure is called
  #     # so we stub it out before it can overwrite @state
  #     allow(@breaker).to receive(:reset_failures)
  #     @breaker.call(success)
  #     expect(@breaker.half_open?).to eq true
  #   end
  #   it 'changes back to open after a successful call' do
  #     @breaker.call(success)
  #     expect(@breaker.closed?).to eq true
  #   end
  # end
  # describe 'logging' do
  #   let(:log_message) { "[StandardError] - #{failure_msg}" }
  #   it 'logs after a failure' do
  #     expect(breaker.logger).to receive(:warn).with(log_message)
  #     breaker.call(failure)
  #   end
  #   it 'logs when the circuit resets' do
  #     reset_timeout = 0.5
  #     breaker = CircuitBreaker.new do |cb|
  #       cb.circuit = -> (arg) { service(arg) }
  #       cb.failure_limit = failure_limit
  #       cb.reset_timeout = reset_timeout
  #     end
  #     msg = "Circuit closed"
  #
  #     expect(breaker.logger).to receive(:info).with(msg)
  #     open_then_close_breaker(breaker)
  #   end
  # end
end
