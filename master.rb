require 'logger'
require './logging'
include Logging
require 'optparse'
require "erubis"

#####
#
#   Runs the statistics for a given dataset
#   IN: dataset_name source_of_tree
#   out:
#   1) Sorted and appropriate sam files
#   2) runs compare2truth
#   3) runs compare junctions
#
####

# 2015/8/10 Katharina Hayer

$logger = Logger.new(STDERR)
$algorithms = [:contextmap2,
      :crac, :gsnap, :hisat, :mapsplice2, :olego, :rum,
      :star, :subjunc, :tophat2]

# Initialize logger
def setup_logger(loglevel)
  case loglevel
  when "debug"
    $logger.level = Logger::DEBUG
  when "warn"
    $logger.level = Logger::WARN
  when "info"
    $logger.level = Logger::INFO
  else
    $logger.level = Logger::ERROR
  end
end

def setup_options(args)
  options = {:out_file =>  "overview_table.xls", :loglevel => "error",
    :algorithm => "all", :transcripts => nil, :junctions_crossed => nil,
    :cig_file => nil, :stats_path => nil, :tool_result_path => nil,
    :aligner_benchmark => nil, :samtools => "samtools", :jobs_path => nil,
    :species => "human"
  }

  opt_parser = OptionParser.new do |opts|
    opts.banner = "\nUsage: ruby master.rb [options] dataset source_of_tree"
    opts.separator ""
    opts.separator "e.g. dataset = t3r1"
    opts.separator "e.g. source_of_tree = /project/itmatlab/aligner_benchmark"
    opts.separator ""
    # enumeration
    opts.on('-a', '--algorithm ENUM', [:all,:contextmap2,
      :crac, :gsnap, :hisat, :mapsplice2, :olego, :rum,
      :star, :subjunc, :tophat2],'Choose from below:','all: DEFAULT',
      'contextmap2','crac','gsnap','hisat', 'mapsplice2',
      'olego','rum','star','subjunc','tophat2') do |v|
      options[:algorithm] = v
    end

    opts.on("-d", "--debug", "Run in debug mode") do |v|
      options[:log_level] = "debug"
    end

    opts.on("-o", "--out_file [OUT_FILE]",
      :REQUIRED,String,
      "File for the output, Default: overview_table.xls") do |anno_file|
      options[:out_file] = anno_file
    end

    opts.on("-s", "--species [String]",
      :REQUIRED,String,
      "Spiecies, Default: human") do |s|
      options[:species] = s
    end

    opts.on("-v", "--verbose", "Run verbosely") do |v|
      options[:log_level] = "info"
    end

    opts.separator ""
  end

  args = ["-h"] if args.length == 0
  opt_parser.parse!(args)
  setup_logger(options[:log_level])
  raise "Please specify the input files" if args.length == 0
  options
end

class Job
  def initialize(jobnumber, cmd, status, working_dir)
    @jobnumber = jobnumber
    @cmd = cmd
    @status = status
    @working_dir = working_dir
  end

  attr_accessor :jobnumber, :cmd, :status

  def to_s
    "Jobnumber #{@jobnumber};\nCmd: #{@cmd};\nStatus: #{@status}\nWD: #{@working_dir}"
  end
end

def check_if_results_exist(stats_path)
  File.exists?("#{stats_path}/comp_res.txt") && File.exists?("#{stats_path}/junctions_stats.txt")
end

def get_truth_files(options, source_of_tree, dataset)
  cmd = "find #{source_of_tree}/jobs/settings/ -name \"*#{options[:species]}*#{dataset}*\""
  $logger.debug(cmd)
  l = `#{cmd}`
  l = l.split("\n")
  raise "Trouble finding #{dataset}: #{l}" if l.length != 1
  l = l[0]
  dir = nil
  File.open(l).each do |line|
    line.chomp!.delete!("\"")
    fields = line.split("=")
    case fields[0]
    when "READS_PATH"
      dir = fields[1]
    when "CIG_FILE"
      options[:cig_file] = "#{dir}/#{fields[1]}"
    when "TRANSCRIPTS"
      options[:transcripts] = "#{dir}/#{fields[1]}"
    when "JUNCTIONS_CROSSED"
      options[:junctions_crossed] = "#{dir}/#{fields[1]}"
    end
  end
  $logger.debug(options)
end

def monitor_jobs(jobs)
  #TODO
end


def run_tophat2(options, source_of_tree, dataset)
  cmd = "find #{source_of_tree}/tool_results/tophat2/alignment -name \"*#{options[:species]}*#{dataset}*\""
  $logger.debug(cmd)
  l = `#{cmd}`
  l = l.split("\n")
  raise "Trouble finding #{dataset}: #{l}" if l.length != 1
  l = l[0]
  erubis = Erubis::Eruby.new(File.read("#{options[:aligner_benchmark]}/templates/tophat2.sh"))
  Dir.glob("#{l}/*").each do |p|
    next unless File.directory? p
    next unless File.exists?("#{p}/unmapped.bam")
    next unless File.exists?("#{p}/accepted_hits.bam")
    $logger.debug(p)
    options[:stats_path] = "#{options[:out_directory]}/tophat2/#{p.split("/")[-1]}"
    begin
      Dir.mkdir(options[:stats_path])
    rescue SystemCallError
      if Dir.exists?(options[:stats_path])
        logger.warn("Directory #{options[:stats_path]} exists!")
      else
        logger.error("Can't create directory #{options[:stats_path]}!")
        raise("Trouble creating directory, log for detials.")
      end
    end

    next if check_if_results_exist(options[:stats_path])

    options[:tool_result_path] = p

    o = File.open("#{options[:jobs_path]}/tophat2_statistics_#{options[:species]}_#{dataset}.sh","w")
    o.puts(erubis.evaluate(options))
    o.close()
    Dir.chdir "#{options[:jobs_path]}"
    $logger.debug(Dir.pwd)
    cmd = "bsub < #{options[:jobs_path]}/tophat2_statistics_#{options[:species]}_#{dataset}.sh"
    options[:jobs] << Job.new(1245, cmd, "queud",Dir.pwd)
  end
  $logger.debug(options[:jobs])
end

def run(argv)
  options = setup_options(argv)
  dataset = argv[0]
  source_of_tree = argv[1]
  options[:aligner_benchmark] = File.expand_path(File.dirname(__FILE__))
  # Results go to
  options[:out_directory] = "#{source_of_tree}/statistics/#{options[:species]}_#{dataset}"
  begin
    Dir.mkdir(options[:out_directory])
  rescue SystemCallError
    if Dir.exists?(options[:out_directory])
      logger.warn("Directory #{options[:out_directory]} exists!")
    else
      logger.error("Can't create directory #{options[:out_directory]}!")
      raise("Trouble creating directory, log for detials.")
    end
  end


  #setup_logger(options[:log_level])
  $logger.info("Hallo")
  $logger.debug("DEBUG")
  $logger.debug(options)
  $logger.debug(argv)


  if options[:algorithm] == "all"
    algorithms = $algorithms
  else
    algorithms = [options[:algorithm]]
  end

  get_truth_files(options, source_of_tree, dataset)

  $logger.debug("Algorithms = #{algorithms}")
  options[:jobs] = []


  algorithms.each do |alg|
    options[:jobs_path] = "#{source_of_tree}/jobs/#{alg}"
    begin
      Dir.mkdir("#{options[:out_directory]}/#{alg}")
    rescue SystemCallError
      if Dir.exists?("#{options[:out_directory]}/#{alg}")
        logger.warn("Directory #{options[:out_directory]}/#{alg} exists!")
      else
        logger.error("Can't create directory #{options[:out_directory]}/#{alg}!")
        raise("Trouble creating directory, log for detials.")
      end
    end
    case alg
    when :tophat2
      run_tophat2(options, source_of_tree, dataset)
    when :star
      puts "LALAA"
    end
  end

  monitor_jobs(options[:jobs])
  #puts options[:cut_off]
  $logger.info("All done!")
end

if __FILE__ == $0
  run(ARGV)
end





