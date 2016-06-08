require File.join(File.dirname(__FILE__), 'Dash.rb')

def add_fragment_for_dash(file, fragment, comment = '/* Added for Dash */')
    File.open(file, 'r+') { |f|
        content = f.read

        break if content.include?(comment)

        f.rewind
        f.puts content, comment, fragment
        f.truncate(f.tell)
    }
end

def index_command(dash, command, doc, parents = [])
    if parents.empty?
        # insert record for general aws command
        remark = ''
        dash.sql_insert(command, 'Command', doc.url)
    else
        # register categories
        # e.g. <li class="toctree-l2"><a class="reference internal" href="reference/autoscaling/index.html">autoscaling</a></li>
        remark = " (#{parents.join(' ')})"
        dash.sql_insert(command + remark, 'Category', doc.url)
    end

    doc.css('.section .headerlink').each do |headerlink|
        case headerlink.parent.name
        when 'h1'
            name = headerlink.at_xpath('./preceding-sibling::text()').content
            newanchor = dash.get_dash_anchor(doc, (parents + [name]).join(' '), 'Command')
        when 'h2'
            name = headerlink.at_xpath('./preceding-sibling::text()').content
            newanchor = dash.get_dash_anchor(doc, name, 'Section')
        else
            next
        end
        headerlink.before(newanchor)
    end

    # insert option anchors and catalog options
    # e.g.
    # <div class="section" id="options">
    # <h2>Options<a class="headerlink" href="#options" title="Permalink to this headline">¶</a></h2>
    # <p><tt class="docutils literal"><span class="pre">--auto-scaling-group-name</span></tt> (string)</p>
    doc.css('#options p > .literal:first-child > span.pre').each do |span|
        option      = span.content
        newanchorid = option[/\-\-(.*)/, 1] or next
        newanchor   = dash.get_dash_anchor(doc, option, 'Option', newanchorid)
        span.before(newanchor)

        dash.sql_insert( option + remark, 'Option', dash.resolve_url(doc.url, '#' + newanchorid) )
    end

    # dip into each category folder and grab the index.html which has links to all commands
    # e.g. <li class="toctree-l1"><a class="reference internal" href="create-auto-scaling-group.html">create-auto-scaling-group</a></li>
    doc.css('li.toctree-l1 a').each do |anchor|
        # register (sub-)command
        subcommand     = anchor.content
        subcommand_url = dash.resolve_url(doc.url, anchor['href'])
        subcommand_doc = dash.get_noko_doc(subcommand_url)

        anchor.before(dash.get_dash_anchor(doc, subcommand, 'Option'))

        index_command(dash, subcommand, subcommand_doc, parents + [command])
    end

    # rewrite the file, free up the memory
    dash.save_noko_doc(doc)
end

dash = Dash.new({
    :name           => 'AWS-CLI',
    :display_name   => 'AWS CLI',
    :docs_root      => File.join('docs.aws.amazon.com', 'cli', 'latest'),
    :icon           => File.join('icon-images', 'aws.png')
})

puts "Beginning the generation of AWS CLI docset..."

add_fragment_for_dash(File.expand_path('_static/guzzle.css', dash.docs_root), <<-'EOS')
.sphinxsidebar {
  display: none;
}
.body {
  float: none;
  width: auto;
}
EOS

add_fragment_for_dash(File.expand_path('_static/bootstrap.min.css', dash.docs_root), <<-'EOS')
.navbar.navbar-fixed-top {
    display: none;
}
EOS

# register the Getting Started link as a guide
dash.sql_insert( 'What Is the AWS Command Line Interface?', 'Guide', 'userguide/cli-chap-welcome.html' )


# let's grab the aws command/options recursively
aws_url = File.join('reference', 'index.html')
aws_doc = dash.get_noko_doc(aws_url)

index_command(dash, 'aws', aws_doc)

# dash.sql_execute({
#     :noop => true,
#     :filter => {
#         :limit => 5,
#         :type => 'Class',
#         :name => 'Exception'
#     }
# })
dash.sql_execute

# dash.copy_docs(:noop => true)
dash.copy_docs()

puts "\nDone."
