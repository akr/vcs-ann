class SVNRepo
  def initialize(root)
    @root = root
    @type = {}
    @cat = {}
    @ann = {}
  end

  def run_info(relpath, rev)
    key = [relpath, rev]
    if !@type.has_key?(key)
      out, err, status = Open3.capture3({"LC_ALL"=>"C"}, "svn", "info", "-r#{rev}", "#{@root}#{relpath}")
      out.force_encoding('locale').scrub!
      err.force_encoding('locale').scrub!
      if !status.success?
        case err
        when /Unable to find repository location/
          @type[key] = :not_exist
        else
          raise "unexpected failing svn info result: #{err}"
        end
      else
        case out
        when /^Node Kind: file$/
          @type[key] = :file
        when /^Node Kind: directory$/
          @type[key] = :dir
        else
          raise "unexpected succeseed svn info result"
        end
      end
    end
    @type[key]
  end

  def run_cat(relpath, rev)
    key = [relpath, rev]
    if !@cat.has_key?(key)
      if run_info(relpath, rev) != :file
        raise "file expected"
      end
      tmpbase = File.basename(relpath) + "-r#{rev}"
      cat = Tempfile.new([tmpbase, ".txt"])
      cat.close
      out, err, status = Open3.capture3({"LC_ALL"=>"C"}, "svn", "cat", "-r#{rev}", "#{@root}#{relpath}")
      out.force_encoding('locale').scrub!
      err.force_encoding('locale').scrub!
      if !status.success?
        raise "svn cat failed"
      end
      cat.open
      cat << out
      cat.close
      @cat[key] = cat
    end
    @cat[key]
  end

  def run_ann(relpath, rev)
    key = [relpath, rev]
    if !@ann.has_key?(key)
      if run_info(relpath, rev) != :file
        raise "file expected"
      end
      tmpbase = File.basename(relpath) + "-r#{rev}"
      ann = Tempfile.new([tmpbase, ".xml"])
      ann.close
      system "svn", "ann", "--xml", "-r#{rev}", "#{@root}#{relpath}", :out => ann.path
      if !$?.success?
        raise "svn ann failed"
      end
      @ann[key] = ann
    end
    @ann[key]
  end

  def format_file(list)
    rev = list[0]
    relpath = list[1..-1].map {|s| "/" + s }.join

    case type = run_info(relpath, rev)
    when :file
    else
      raise "unexpected type #{type}: #{relpath}@#{rev}"
    end

    cat = run_cat(relpath, rev)
    if !cat
      raise "not a plain file: #{relpath}@#{rev}"
    end

    ann = run_ann(relpath, rev)
    ann.open
    lines = []
    ann.each("</entry>\n") {|entry|
      next if /<entry\n/ !~ entry
      entry = $'
      next if /line-number="(\d+)"/ !~ entry
      line_number = $1
      next if /revision="(\d+)"/ !~ entry
      line_rev = $1
      next if %r{<author>(.*)</author>} !~ entry
      line_author = CGI.unescapeHTML($1)
      next if %r{<date>(.*)</date>} !~ entry
      line_date = $1
      lines << [line_number, line_rev, line_author, line_date]
    }
    ann.close

    width_list = lines.map {|line_number, line_rev, line_author, line_date|
      [line_number.length, line_rev.length, line_author.length]
    }
    line_number_width = width_list.map {|ln_width, rev_width, authoer_width| ln_width }.max
    line_rev_width = width_list.map {|ln_width, rev_width, authoer_width| rev_width }.max
    line_author_width = width_list.map {|ln_width, rev_width, author_width| author_width }.max

    result = "<pre>"
    prev_rev = nil
    cat.open
    cat.each.with_index {|line, i|
      line.expand_tab!
      ln = i+1
      line_number, line_rev, line_author, line_date = lines[i]
      commit_url = "/commit/#{line_rev}\##{u line_rev+':'+line.chomp}"
      authorsp = line_author.ljust(line_author_width)
      line_number_anchor = ln.to_s
      line_contents_anchor = u line.chomp
      if prev_rev != line_rev
        revsp = line_rev.rjust(line_rev_width)
        prev_rev = line_rev
      else
        revsp = ' ' * line_rev_width
      end
      result << %{<a name="#{h line_number_anchor}"></a>}
      result << %{<a name="#{h line_contents_anchor}"></a>}
      result << %{<a href="#{h commit_url}" title="#{h line_date}">#{h revsp}</a> }
      result << "#{h authorsp} #{h line.chomp}\n"
    }
    cat.close
    result << "</pre>"
    result
  end

  def format_commit(list)
    rev = list[0]
    log_out, log_err, log_status = Open3.capture3({"LC_ALL"=>"C"}, "svn", "log", "-r#{rev}", "#{@root}")
    diff_out, diff_err, diff_status = Open3.capture3({"LC_ALL"=>"C"}, "svn", "diff", "-c#{rev}", "#{@root}")
    log_out.force_encoding('locale').scrub!
    log_err.force_encoding('locale').scrub!
    diff_out.force_encoding('locale').scrub!
    diff_err.force_encoding('locale').scrub!

    rev_hash = {}
    diff_out.each_line {|line|
      next if /\A(?:---|\+\+\+)\s+(\S+)\s+\(revision (\d+)\)/ !~ line
      filename = $1
      rev = $2
      rev_hash[rev] = true
    }
    rev_maxwidth = rev_hash.keys.map {|rev| rev.length }.max
    rev_space = " " * rev_maxwidth
    rev_fmt = "%.#{rev_maxwidth}s"

    result = ''

    result << '<pre>'
    log_out.each_line {|line|
      result << (h line.chomp) << "\n"
    }
    result << '</pre>'

    rev1 = (rev.to_i-1).to_s
    rev2 = rev
    filename1 = filename2 = '?'
    result << '<pre>'
    scan_udiff(diff_out) {|tag, *rest|
      case tag
      when :filename1
        line, filename1 = rest
        result << " "
        result << (h line.chomp) << "\n"
      when :filename2
        line, filename2 = rest
        result << " "
        result << (h line.chomp) << "\n"
      when :hunk_header
        line, ln_cur1, ln_num1, ln_cur2, ln_num2 = rest
        result << " "
        result << (h line.chomp) << "\n"
      when :del
        line, content_line, ln_cur1 = rest
        content_line = content_line.chomp.expand_tab
        rev1_url = "/file/#{rev1}/#{filename1}\##{ln_cur1}"
        result << %{<a name="#{h(u(rev1.to_s+"/"+filename1+":"+ln_cur1.to_s))}"></a>}
        result << %{<a name="#{h(u(rev1.to_s+":"+content_line.chomp))}"></a>}
        result << %{<a href="#{h rev1_url}"> -</a>}
        result << (h content_line) << "\n"
      when :add
        line, content_line, ln_cur2 = rest
        content_line = content_line.chomp.expand_tab
        rev2_url = "/file/#{rev2}/#{filename2}\##{ln_cur2}"
        result << %{<a name="#{h(u(rev2.to_s+"/"+filename2+":"+ln_cur2.to_s))}"></a>}
        result << %{<a name="#{h(u(rev2.to_s+":"+content_line.chomp))}"></a>}
        result << %{<a href="#{h rev2_url}"> +</a>}
        result << (h content_line) << "\n"
      when :com
        line, content_line, ln_cur1, ln_cur2 = rest
        content_line = content_line.chomp.expand_tab
        rev1_url = "/file/#{rev1}/#{filename1}\##{ln_cur1}"
        rev2_url = "/file/#{rev2}/#{filename2}\##{ln_cur2}"
        result << %{<a name="#{h(u(rev1.to_s+"/"+filename1+":"+ln_cur1.to_s))}"></a>}
        result << %{<a name="#{h(u(rev2.to_s+"/"+filename2+":"+ln_cur2.to_s))}"></a>}
        result << %{<a name="#{h(u(rev1.to_s+":"+content_line.chomp))}"></a>}
        result << %{<a name="#{h(u(rev2.to_s+":"+content_line.chomp))}"></a>}
        result << %{<a href="#{h rev1_url}"> </a>}
        result << %{<a href="#{h rev2_url}"> </a>}
        result << (h content_line) << "\n"
      when :other
        line, = rest
        result << " "
        result << (h line.chomp) << "\n"
      else
        raise "unexpected udiff line tag"
      end
    }
    result << '</pre>'

    result
  end
end
