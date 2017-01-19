require 'ruby-progressbar'
require 'thwait'

module GasLoadTester
  class Test
    attr_accessor :client, :time, :results

    DEFAULT = {
      client: 1000,
      time: 300
    }

    def initialize(args = {})
      args ||= {}
      args[:client] ||= args['client']
      args[:time] ||= args['time']
      args.reject!{|key, value| value.nil? }
      args = DEFAULT.merge(args)

      self.client = args[:client]
      self.time = args[:time]
      self.results = {}
      @run = false
    end

    def run(args = {}, &block)
      args ||= {}
      args[:output] ||= args['output']
      args[:file_name] ||= args['file_name']
      puts "Running test (client: #{self.client}, time: #{self.time})"
      @progressbar = ProgressBar.create(
        :title => "Load test",
        :starting_at => 0,
        :total => self.time+10,
        :format => "%a %b\u{15E7}%i %p%% %t",
        :progress_mark  => ' ',
        :remainder_mark => "\u{FF65}"
      )
      load_test(block)
      if args[:output]
        export_file({file_name: args[:file_name]})
      end
    ensure
      @run = true
    end

    def is_run?
      @run
    end

    def request_per_second
      (self.client/self.time.to_f).ceil
    end

    def export_file(args = {})
      args ||= {}
      file = args[:file_name] || ''
      chart_builder = GasLoadTester::ChartBuilder.new(file_name: file)
      chart_builder.build_body(self)
      chart_builder.save
    end

    def summary_min_time
      all_result_time.sort.first*1000
    end

    def summary_max_time
      all_result_time.sort.last*1000
    end

    def summary_avg_time
      all_result_time.sum.fdiv(all_result_time.size)*1000
    end

    def summary_success
      self.results.collect{|key, values| values.select{|val| val.pass }.count }.flatten.sum
    end

    def summary_error
      self.results.collect{|key, values| values.select{|val| !val.pass }.count }.flatten.sum
    end

    private

    def all_result_time
      self.results.collect{|key, values| values.collect(&:time) }.flatten
    end

    def load_test(block)
      threads = []
      rps = request_per_second
      self.time.times do |index|
        self.results[index] = []
        start_index_time = Time.now
        rps.times do
          threads << Thread.new do
            begin
              start_time = Time.now
              block.call
              self.results[index] << build_result({pass: true, time: Time.now-start_time})
            rescue => error
              self.results[index] << build_result({pass: false, error: error, time: Time.now-start_time})
            end
          end
        end
        cal_sleep = 1-(Time.now-start_index_time)
        cal_sleep = 0 if cal_sleep < 0
        sleep(cal_sleep)
        @progressbar.increment
      end
      ThreadsWait.all_waits(*threads)
      @progressbar.progress += 10
    end

    def build_result(args)
      Result.new(args)
    end

  end
end
