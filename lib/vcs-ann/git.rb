class GITRepo
  def initialize(topdir)
    @topdir = topdir
  end

  def git_blame_each(topdir, relpath, rev)
    out, status = Open3.capture2('git', '-C', topdir, 'blame', '--porcelain', rev, '--', relpath)
    out.force_encoding('locale').scrub!
    if !status.success?
      raise "git blame failed"
    end

    header_hash = {}
    prev_header = {}
    block = []
    out.each_line {|line|
      line.force_encoding('locale').scrub!
      if /\A\t/ !~ line
        block << line
      else
        content_line = line.sub(/\A\t/, '')
        rev, original_file_line_number, final_file_line_number, numlines = block.shift.split(/\s+/)
        if !block.empty?
          header = {}
          block.each {|header_line|
            if / / =~ header_line.chomp
              header[$`] = $'
            end
          }
          header_hash[rev] = header
        end
        header = header_hash[rev]
        yield rev, original_file_line_number, final_file_line_number, numlines, header, content_line
        block = []
      end
    }
  end

  def format_file(list)
    rev = list[0]
    relpath = list[1..-1].join('/')

    result = '<pre>'

    data = []
    author_name_width = 0
    git_blame_each(@topdir.to_s, relpath, rev) {|rev, original_file_line_number, final_file_line_number, numlines, header, content_line|
      author_time = Time.at(header['author-time'].to_i).strftime("%Y-%m-%d")
      author_name = header['author']
      content_line = content_line.chomp.expand_tab
      author_name_width = author_name.length if author_name_width < author_name.length
      data << [rev, author_time, author_name, content_line, header['filename'], original_file_line_number]
    }

    prev_rev = nil
    ln = 1
    data.each {|rev, author_time, author_name, content_line, filename, original_file_line_number|
      formatted_author_time = prev_rev == rev ? ' ' * 10 : author_time
      formatted_author_name = "%-#{author_name_width}s" % author_name
      commit_url = "/commit/#{rev}\##{u(rev+"/"+filename.to_s+":"+original_file_line_number.to_s)}"
      result << %{<a name="#{h ln.to_s}"></a>}
      result << %{<a href="#{h commit_url}">#{h formatted_author_time}</a> }
      result << %{#{h formatted_author_name} }
      result << %{#{h content_line}\n}
      prev_rev = rev
      ln += 1
    }

    result << '</pre>'

    result
  end

  def format_commit(list)
    rev = list[0]
    rev
    log_out, log_status = Open3.capture2({'LC_ALL'=>'C'},
       'git', '-C', @topdir.to_s, 'log', '-1', '--parents', rev)
    log_out.force_encoding('locale').scrub!
    if !log_status.success?
      raise "git log failed."
    end

    if /^commit ([0-9a-f]+)(.*)\n/ !~ log_out
      raise "git log doesn't produce 'commit' line."
    end
    commit_rev = $1
    parent_revs = $2.strip.split(/\s+/)

    result = '<pre>'
    log_out.each_line {|line|
      result << "#{h line.chomp}\n"
    }
    result << '</pre>'

    parent_revs.each {|parent_rev|
      diff_out, diff_status = Open3.capture2({'LC_ALL'=>'C'},
         'git', '-C', @topdir.to_s, 'diff', parent_rev, commit_rev)
      diff_out.force_encoding('locale').scrub!
      if !diff_status.success?
        raise "git diff failed."
      end

      rev1 = parent_rev
      rev2 = commit_rev
      filename1 = filename2 = '?'
      result << '<pre>'
      scan_udiff(diff_out) {|tag, *rest|
        case tag
        when :filename1
          line, filename1 = rest
          filename1.sub!(%r{\Aa/}, '')
          result << " "
          result << (h line.chomp.expand_tab) << "\n"
        when :filename2
          line, filename2 = rest
          filename2.sub!(%r{\Ab/}, '')
          result << " "
          result << (h line.chomp.expand_tab) << "\n"
        when :hunk_header
          line, ln_cur1, ln_num1, ln_cur2, ln_num2 = rest
          result << " "
          result << (h line.chomp.expand_tab) << "\n"
        when :del
          line, content_line, ln_cur1 = rest
          content_line = content_line.chomp.expand_tab
          rev1_url = "/file/#{rev1}/#{filename1}\##{ln_cur1}"
          result << %{<a name="#{h(u(rev1.to_s+"/"+filename1+":"+ln_cur1.to_s))}"></a>}
          result << %{<a href="#{h rev1_url}"> -</a>}
          result << (h content_line) << "\n"
        when :add
          line, content_line, ln_cur2 = rest
          content_line = content_line.chomp.expand_tab
          rev2_url = "/file/#{rev2}/#{filename2}\##{ln_cur2}"
          result << %{<a name="#{h(u(rev2.to_s+"/"+filename2+":"+ln_cur2.to_s))}"></a>}
          result << %{<a href="#{h rev2_url}"> +</a>}
          result << (h content_line) << "\n"
        when :com
          line, content_line, ln_cur1, ln_cur2 = rest
          content_line = content_line.chomp.expand_tab
          rev1_url = "/file/#{rev1}/#{filename1}\##{ln_cur1}"
          rev2_url = "/file/#{rev2}/#{filename2}\##{ln_cur2}"
          result << %{<a name="#{h(u(rev1.to_s+"/"+filename1+":"+ln_cur1.to_s))}"></a>}
          result << %{<a name="#{h(u(rev2.to_s+"/"+filename2+":"+ln_cur2.to_s))}"></a>}
          result << %{<a href="#{h rev1_url}"> </a>}
          result << %{<a href="#{h rev2_url}"> </a>}
          result << (h content_line) << "\n"
        when :other
          line, = rest
          result << " "
          result << (h line.chomp.expand_tab) << "\n"
        else
          raise "unexpected udiff line tag"
        end
      }
      result << '</pre>'

    }

    result
  end
end
