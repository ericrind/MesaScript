InlistItem = Struct.new(:name, :type, :value, :namelist, :order, :is_arr?,
:flagged)

class Inlist


  @inlist_data = {}
  # Different namelists can be added or subtracted if MESA should change or
  # proprietary inlists are required. Later hashes should be edited in a
  # similar way to get the desired behavior for additional namelists.

  #################### ADD NEW NAMELISTS HERE ####################
  @namelists = %w{ star_job controls pgstar }
  ################## POINT TO .INC FILES HERE ####################
  @nt_files = {
                'star_job' => 'star_job_controls.inc',
                'controls' => 'star_controls.inc',
                'pgstar'   => 'pgstar_controls.inc'
              }
  # User can specify a custom name for a namelist defaults file. The default
  # is simply the namelist name followed by '.defaults'

  ################ POINT TO .DEFAULTS FILES HERE #################
  @d_files = {}

  # User can add new paths to namelist default files through this hash

  ############ GIVE PATHS TO .INC AND .DEF FILES HERE ###########
  @nt_paths = Hash.new(ENV['MESA_DIR'] + '/star/private/')
  @d_paths = Hash.new(ENV['MESA_DIR'] + '/star/defaults/')


############### NO MORE [SIMPLE] USER-CUSTOMIZABLE FEATURES BELOW ##############

  # This tells the class to initialize its structure if it hasn't already.
  # If new namelists are added after an instance is initialized, this can be
  # redone manually by the Inlist.get_data command.
  @have_data = false

  # Set up interface to access/change customizable inlist initialization data.
  # Establish class instance variables
  class << self
    attr_accessor :have_data
    attr_accessor :namelists, :nt_paths, :d_paths, :inlist_data, :d_files,
                  :nt_files
  end

  # Generate methods for the Inlist class that set various namelist parameters.
  def self.get_data
    Inlist.namelists.each do |namelist|
      @inlist_data[namelist] = Inlist.get_namelist_data(namelist,
        Inlist.nt_files[namelist], Inlist.d_files[namelist])
    end
    # create methods (interface) for each data category
    @inlist_data.each_value do |namelist_data|
      namelist_data.each do |datum|
        if datum.is_arr?
          Inlist.make_parentheses_method(datum)
        else
          Inlist.make_regular_method(datum)
        end
      end
    end
    # don't do this nonsense again unles specifically told to do so
    Inlist.have_data = true
  end

  # Three ways to access array categories. All methods will cause the
  # data category to be staged into your inlist, even if you do not change it
  # Basically, if it appears in your mesascript, it will definitely appear
  # in your inlist. There is no way to unflag an entry.
  #
  # 1. Standard array way like
  #        xa_lower_limit_species[1] = 'h1'
  #    (note square braces, NOT parentheses). Returns new value.
  #
  # 2. Just access (and flag), but don't change via array access, like
  #        xa_lower_limit_species[1]
  #    (again, note square braces). Returns current value
  #
  # 3. No braces method, like
  #        xa_lower_limit_species()           # flags and returns hash of values
  #        xa_lower_limit_species             # same, but more ruby-esque
  #        xa_lower_limit_species(1)          # flags and returns value 1
  #        xa_lower_limit_species 1           # Same
  #        xa_lower_limit_species(1, 'h1')    # flags and sets value 1
  #        xa_lower_limit_species 1, 'h1'     # same
  def self.make_parentheses_method(datum)
    name = datum.name
    define_method(name + '[]=') do|arg1, arg2|
      self.flag_command(name)
      self.data_hash[name].value[args1] = arg2
    end
    define_method(name + '[]') do |arg|
      self.flag_command(name)
      self.data_hash[name].value[arg]
    end
    define_method(name) do |*args|
      self.flag_command(name)
      return self.data_hash[name].value if args.empty?
      self.data_hash[name].value[args[0]] if args.size == 1
      self.data_hash[name].value[args[0]] = args[1] if args.size == 2
      raise "Invalid number of arguments (expected 0, 1, or 2) for method #{name}." if args.size > 2
    end
    alias_method name.downcase.to_sym, name.to_sym
    alias_method (name.downcase + '[]').to_sym, (name + '[]').to_sym
    alias_method (name.downcase + '[]=').to_sym, (name + '[]=').to_sym
  end

  # Two ways to access/change scalars. All methods will cause the data category
  # to be staged into your inlist, even if you do not change the value.
  # Basically, if it appears in your mesascript, it will definitely appear in
  # your inlist. There is no way to unflag an entry.
  #
  # 1. Change value, like
  #        initial_mass(1.0)
  #        initial_mass 1.0
  #    This flags the category to go in your inlist and changes the value. There
  #    is no difference between these two syntaxes (it's built into ruby).
  #    Returns new value.
  #
  # 2. Just access, like
  #        initial_mass()
  #        initial_mass
  #    This flags the category, but does not change the value. Again, both
  #    syntaxes are allowed, though the one without parentheses is more
  #    traditional for ruby (why do you want empty parentheses anyway?). Returns
  #    current value.

  def self.make_regular_method(datum)
    name = datum.name
    define_method(name) do |*args|
      self.flag_command(name)
      return self.data_hash[name].value unless args[0]
      self.data_hash[name].value = args[0]
    end
    aliases = [(name + '=').to_sym,
               (name.downcase + '=').to_sym,
               name.downcase.to_sym]
    aliases.each { |ali| alias_method ali, name.to_sym }
  end


  # Ensure provided value's data type matches expected data type. Then convert
  # to string for printing to an inlist. If value is a string, change nothing
  # (no protection). If value is a string and SHOULD be a string, wrap it in
  # single quotes.
  def self.parse_input(name, value, type)
    if value.class == String
      return "'#{value}'" if type == :string
      return value
    elsif type == :bool
      unless [TrueClass, FalseClass].include?(value.class)
        raise "Invalid value for namelist item #{name}: #{value}. Use " +
        "'.true.', '.false.', or a Ruby boolean (true/false)."
      end
      if value == true
        return '.true.'
      elsif value == false
        return '.false.'
      else
        raise "Error converting value #{value} of #{name} to a boolean."
      end
    elsif type == :int
      raise "Invalid value for namelist item #{name}: #{value}. Must provide"+
      " an int or float." unless value.is_a?(Integer) or value.is_a?(Float)
      if value.is_a?(Float)
        puts "WARNING: Expected integer for #{name} but got #{value}. Value " +         " will be converted to an integer."
      end
      return value.to_i.to_s
    elsif type == :float
      raise "Invalid value for namelist item #{name}: #{value}. Must provide " +
      "an int or float." unless value.is_a?(Integer) or value.is_a?(Float)
      return sprintf("%g", value).sub('e', 'd')
    elsif type == :type
      puts "WARNING: 'type' values are currently unsupported (regarding #{name}) because your humble author has no idea what they look like in an inlist. You should tell him what to do at wmwolf@physics.ucsb.edu. Your input, #{value}, has been passed through to your inlist verbatim."
      return value.to_s
    else
      raise "Error parsing value for namelist item #{name}: #{value}. Expected type was #{type}."
    end
  end

  # Converts a standard inlist to its equivalent mesascript formulation.
  # Comments are preserved and namelist separators are converted to comments.
  # Note that comments do NOT get put back into the fortran inlist through
  # mesascript. Converting an inlist to mesascript and then back again will
  # clean up and re-order your inlist, but all comments will be lost. All other
  # information SHOULD remain intact.
  def self.inlist_to_mesascript(inlist_file, script_file, dbg = false)
    Inlist.get_data unless Inlist.have_data       # ensure we have inlist data
    inlist_contents = File.readlines(inlist_file)

    # make namelist separators comments
    new_contents = inlist_contents.map do |line|
      case line
      when /^\s*&/  then '# ' + line.chomp        # start namelist
      when /^\s*\// then '# ' + line.chomp        # end namelist
      else
        line.sub('!', '#').chomp                  # fix comments
      end
    end
    new_contents.map! do |line|
      if line =~ /^\s*#/ or line.strip.empty?     # leave comments and blanks
        result = line
      else
        if dbg
          puts "parsing line:"
          puts line
        end
        comment_pivot = line.index('#')
        if comment_pivot
          command = line[0...comment_pivot]
          comment = line[comment_pivot..-1].to_s.strip
        else
          command = line
          comment = ''
        end
        command =~ /(^\s*)/                       # save leading space
        leading_space = Regexp.last_match(1)
        command =~ /(\s*$)/                       # save buffer space
        buffer_space = Regexp.last_match(1)
        command.strip!                            # remove white space
        name, value = command.split('=').map { |datum| datum.strip }
        if dbg
          puts "name: #{name}"
          puts "value: #{value}"
        end
        if name =~ /\((\d+)\)/                    # fix array assignments
          name.sub!('(', '[')
          name.sub!(')', ']')
          name = name + ' ='
        end
        name.downcase!
        if value =~ /'*.'/ or value =~ /"*."/
          result = name + ' ' + value             # leave strings alone
        elsif %w[.true. .false.].include?(value.downcase)
          result = name + ' ' + value.downcase.gsub('.', '') # fix booleans
        elsif value.include?('.') or value.include?('d') or value.include?('e')
          result = name + ' ' + value.sub('d', 'e')          # fix floats
        else
          result = name + ' ' + value             # leave everything else alone
        end
        result = leading_space + result + buffer_space + comment
        if dbg
          puts "parsed to:"
          puts result
          puts ''
        end
      end
      result
    end
    File.open(script_file, 'w') do |f|
      f.puts "require './mesa_script'"
      f.puts ''
      f.puts "Inlist.make_inlist('#{File.basename(inlist_file)}') do"
      new_contents.each { |line| f.puts '  ' + line }
      f.puts "end"
    end
  end


  # Create an Inlist object, execute block of commands that presumably populate
  # the inlist, then write the inlist to a file with the given name. This is
  # the money routine with user-supplied commands in the instance_eval block.
  def self.make_inlist(name = 'inlist', &block)
    inlist = Inlist.new
    inlist.instance_eval(&block)
    inlist.stage_flagged
    File.open(name, 'w') { |f| f.write(inlist) }
  end

  # Checks to see if the data/methods for the Inlist class has been initialized.
  def self.have_data?
    @have_data
  end

  # Reads names and types for a specified namelist from given file (intended
  # to be of the form of something like star/private/star_controls.inc).
  #
  # Returns an array of InlistItem Struct instances that contain a parameter's
  # name, type (:bool, :string, :float, :int, or :type), the namelist it
  # belongs to, and its relative ordering in that namelist. Bogus defaults are
  # assigned according to the object's type, and the ordering is unknown.

  def self.get_namelist_data(namelist, nt_filename = nil, d_filename = nil)
    temp_data = Inlist.get_names_and_types(namelist, nt_filename)
    Inlist.get_defaults(temp_data, namelist, d_filename)
  end

  def self.get_names_and_types(namelist, nt_filename = nil)
    nt_filename ||= Inlist.nt_files[namelist]
    nt_full_path = Inlist.nt_paths[namelist] + nt_filename
    raise "Couldn't find file #{nt_filename}" unless File.exists?(nt_full_path)
    contents = File.readlines(nt_full_path)

    # Throw out comments and blank lines, ensure remaining lines are a proper
    # Fortran assignment, then remove leading and trailing white space
    contents.reject! { |line| is_comment?(line) or is_blank?(line) }
    contents.map! do |line|
      my_line = line.dup
      my_line = my_line[0...my_line.index('!')] if has_comment?(my_line)
      my_line.strip!
    end
    full_lines = []
    contents.each_with_index do |line, i|
      next unless line =~ /::/
      full_lines << Inlist.full_line(contents, i)
    end
    pairs = full_lines.map { |line| line.split('::').map { |datum| datum.strip}}
    namelist_data = []
    pairs.each do |pair|
      type = case pair[0]
      when /logical/ then :bool
      when /character/ then :string
      when /real/ then :float
      when /integer/ then :int
      when /type/ then :type
      else
        raise "Couldn't determine type of entry #{pair[0]} in #{nt_full_path}."
      end
      names = pair[1].split(',').map { |name| name.strip }
      names.each do |name|
        is_arr = false
        if name =~ /\(.*\)/
          is_arr = true
          name.sub!(/\(.*\)/, '')
        end
        type_default = {:bool => false, :string => '', :float => 0.0, :int => 0}
        dft = is_arr ? Hash.new(type_default[type]) : type_default[type]
        namelist_data << InlistItem.new(name, type, dft, namelist, -1, is_arr)
      end
    end
    namelist_data
  end

  # Similar to Inlist.get_names_and_types, but takes the output of
  # Inlist.get_names_and_types and assigns defaults and orders to each item.
  # Looks for this information in the specified defaults filename.

  def self.get_defaults(temp_data, namelist, d_filename = nil, whine = false)
    d_filename ||= namelist + '.defaults'
    d_full_path = Inlist.d_paths[namelist] + d_filename
    raise "Couldn't find file #{d_filename}" unless File.exists?(d_full_path)
    contents = File.readlines(d_full_path)
    contents.reject! { |line| is_comment?(line) or is_blank?(line) }
    contents.map! do |line|
      my_line = line.dup
      if has_comment?(line)
        my_line = my_line[0...my_line.index('!')]
      end
      raise "Equal sign missing in line:\n\t #{my_line}\n in file " +
        "#{full_path}." unless my_line =~ /=/
      my_line.strip!
    end
    pairs = contents.map {|line| line.split('=').map {|datum| datum.strip}}
    n_d_hash = {}
    n_o_hash = {}
    pairs.each_with_index do |pair, i|
      name = pair[0]
      default = pair[1]
      if name =~ /\(.*\)/
        selector = name[/\(.*\)/][1..-2]
        name.sub!(/\(.*\)/, '')
        if selector == ':'
          default = Hash.new(default)
        else
          default = {selector.to_i => default}
        end
      end
      n_d_hash[name] = default
      n_o_hash[name] = i
    end
    temp_data.each do |datum|
      unless n_d_hash.keys.include?(datum.name)
        puts "WARNING: no default found for control #{datum.name}. Using standard defaults." if whine
      end
      default = n_d_hash[datum.name]
      if default.is_a?(Hash) and datum.value.is_a?(Hash)
        datum.value = datum.value.merge(default)
      else
        datum.value ||= default
      end
      datum.order = n_o_hash[datum.name] || datum.order
    end
    temp_data
  end

  def self.full_line(lines, i)
    return lines[i] unless lines[i][-1] == '&'
    [lines[i].sub('&', ''), full_line(lines, i+1)].join(' ')
  end

  def self.is_comment?(line)
    line =~ /\A\s*!/
  end

  def self.is_blank?(line)
    not (line =~/[a-z0-9]+/)
  end

  def self.has_comment?(line)
    line.include?('!')
  end

  # Making an instance of Inlist first checks to see if the class methods are
  # set up for the namelists in Inlist.namelists. If they aren't ready, it
  # creates them. Then creates a hash with an array associated to each namelist
  # that is the exact size of the number of entries available in that namelist.

  attr_accessor :data_hash
  attr_reader :names
  def initialize
    Inlist.get_data unless Inlist.have_data?
    @data = Inlist.inlist_data
    @data_hash = {}
    @data.each_value do |namelist_data|
      namelist_data.each do |datum|
        @data_hash[datum.name] = datum.dup

      end
    end
    @names = @data_hash.keys
    @data = {}
    Inlist.namelists.each do |namelist|
      @data[namelist] = Array.new(Inlist.inlist_data[namelist].size, '')
    end
  end

  # Zeroes out all staged data and blank lines
  def make_fresh_writelist
    @to_write = {}
    @data.keys.each do |namelist|
      @to_write[namelist] = Array.new(@data[namelist].size, '')
    end
  end

  def namelists
    @data.keys
  end

  def flag_command(name)
    @data_hash[name].flagged = true
  end

  def stage_namelist_command(name)
    datum = @data_hash[name]
    if datum.is_arr?
      lines = @data_hash[name].value.keys.map do |key|
        "  " + datum.name + '(' + key.to_s + ')' + ' = ' +
        Inlist.parse_input(datum.name, datum.value[key], datum.type) + "\n"
      end
      lines = lines.join
      @to_write[datum.namelist][datum.order] = lines
    else
      @to_write[datum.namelist][datum.order] =  "  " + datum.name + ' = ' +
                Inlist.parse_input(datum.name, datum.value, datum.type) + "\n"
    end
  end

  # Marks a data category so that it can be staged into an inlist
  def flagged
    @data_hash.keys.select { |key| @data_hash[key].flagged }
  end

  # Collects all data categories into a hash of arrays (each array is a
  # namelist) that is read whenever the inlist is converted to a string
  # (i.e. when it is printed to a file or the screen).
  def stage_flagged
    make_fresh_writelist # start from scratch

    flagged.each { |name| stage_namelist_command(name) } # stage each datum

    # blank lines between disparate data
    namelists.each do |namelist|
      @to_write[namelist].each_index do |i|
        next if (i == 0 or i == @to_write[namelist].size - 1)
        this_line = @to_write[namelist][i]
        prev_line = @to_write[namelist][i-1]
        if this_line.empty? and not(prev_line.empty? or prev_line == "\n")
          @to_write[namelist][i] = "\n"
        end
      end
    end
  end

  # Takes the staged data categories and formats them into a string series of
  # namelists that are MESA-readable.
  def to_s
    result = ''
    namelists.each do |namelist|
      result += "\n&#{namelist}\n"
      result += @to_write[namelist].join("")
      result += "\n/ ! end of #{namelist} namelist\n"
    end
    result.sub("\n\n\n", "\n\n")
  end

end
