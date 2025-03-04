module Wice
  module GridViewHelper
    # View helper for rendering the grid.
    #
    # The first parameter is a grid object returned by +initialize_grid+ in the controller.
    #
    # The second parameter is a hash of options:
    # * <tt>:html</tt> - a hash of HTML attributes to be included into the <tt>table</tt> tag.
    # * <tt>:class</tt> - a shortcut for <tt>html: {class: 'css_class'}</tt>
    # * <tt>:header_tr_html</tt> - a hash of HTML attributes to be included into the first <tt>tr</tt> tag
    #   (or two first <tt>tr</tt>'s if the filter row is present).
    # * <tt>:show_filters</tt> - defines when the filter is shown. Possible values are:
    #   * <tt>:when_filtered</tt> - the filter is shown when the current table is the result of filtering
    #   * <tt>:always</tt> or <tt>true</tt>  - show the filter always
    #   * <tt>:no</tt> or <tt>false</tt>     - never show the filter
    # * <tt>:upper_pagination_panel</tt> - a boolean value which defines whether there is an additional pagination
    #   panel on top of the table. By default it is false.
    # * <tt>:extra_request_parameters</tt> - a hash which will be added as additional HTTP request parameters to all
    #   links generated by the grid, be it sorting links, filters, or the 'Reset Filter' icon.
    #   Please note that WiceGrid respects and retains all request parameters already present in the URL which
    #   formed the page, so there is no need to enumerate them in <tt>:extra_request_parameters</tt>. A typical
    #   usage of <tt>:extra_request_parameters</tt> is a page with javascript tabs - changing the active tab
    #   does not reload the page, but if one such tab contains a WiceGrid, it could be required that if the user
    #   orders or filters the grid, the result page should have the tab with the grid activated. For this we
    #   need to send an additional parameter specifying from which tab the request was generated.
    # * <tt>:sorting_dependant_row_cycling</tt> - When set to true (by default it is false) the row styles +odd+
    #   and +even+ will be changed only when the content of the cell belonging to the sorted column changes.
    #   In other words, rows with identical values in the ordered column will have the same style (color).
    # * <tt>:allow_showing_all_records</tt> - allow or prohibit the "All Records" mode.
    # * <tt>:hide_reset_button</tt> - Do not show the default Filter Reset button.
    #   Useful when using a custom reset button.
    #   By default it is false.
    # * <tt>:hide_submit_button</tt> - Do not show the default Filter Submit button.
    #   Useful when using a custom submit button
    #   By default it is false.
    # * <tt>:hide_xlsx_button</tt> - a boolean value which defines whether the default Export To XLSX button
    #   should be rendered. Useful when using a custom Export To XLSX button.
    #   By default it is false.
    #   Please read README for more insights.
    #
    # The block contains definitions of grid columns using the +column+ method sent to the object yielded into
    # the block. In other words, the value returned by each of the blocks defines the content of a cell, the
    # first block is called for cells of the first column for each row (each ActiveRecord instance), the
    # second block is called for cells of the second column, and so on. See the example:
    #
    #   <%= grid(@accounts_grid, html: {class: 'grid_style', id: 'accounts_grid'}, header_tr_html: {class: 'grid_headers'}) do |g|
    #
    #     g.column name: 'Username', attribute: 'username' do |account|
    #       account.username
    #     end
    #
    #     g.column name: 'application_account.field.identity_id'._, attribute: 'firstname', model:  Person do |account|
    #       link_to(account.identity.name, identity_path(account.identity))
    #     end
    #
    #     g.column do |account|
    #       link_to('Edit', edit_account_path(account))
    #     end
    #
    #   end -%>
    #
    #
    # Defaults for parameters <tt>:show_filters</tt> and <tt>:upper_pagination_panel</tt>
    # can be changed in <tt>lib/wice_grid_config.rb</tt> using constants <tt>Wice::Defaults::SHOW_FILTER</tt> and
    # <tt>WiceGrid::Defaults::SHOW_UPPER_PAGINATION_PANEL</tt>, this is convenient if you want to set a project wide setting
    # without having to repeat it for every grid instance.
    #
    # Pease read documentation about the +column+ method to achieve the enlightenment.

    def grid(grid, opts = {}, &block)
      raise WiceGridArgumentError.new('Missing block for the grid helper.' \
        ' For detached filters use first define_grid with the same API as grid, ' \
        'then grid_filter to add filters, and then render_grid to actually show the grid') if block.nil?
      define_grid(grid, opts, &block)
      render_grid(grid)
    end

    # Has the same parameters as <tt>grid</tt> but does not output the grid. After <tt>define_grid</tt>
    # <tt>render_grid</tt> can be used to output the grid HTML code.
    # Usually used with detached filters: first <tt>define_grid</tt>, then <tt>grid_filter</tt>s, and then
    # <tt>render_grid</tt>
    def define_grid(grid, opts = {}, &block)
      # strip the method from HTML stuff
      unless grid.class == WiceGrid
        raise WiceGridArgumentError.new('The first argument for the grid helper must be an instance of the WiceGrid class')
      end

      options = {
        allow_showing_all_records:      Defaults::ALLOW_SHOWING_ALL_RECORDS,
        class:                          nil,
        extra_request_parameters:       {},
        header_tr_html:                 {},
        hide_reset_button:              false,
        hide_submit_button:             false,
        hide_xlsx_button:                false,
        show_filters:                   Defaults::SHOW_FILTER,
        sorting_dependant_row_cycling:  false,
        html:                           {},
        upper_pagination_panel:         Defaults::SHOW_UPPER_PAGINATION_PANEL,
        pagination_theme:               ConfigurationProvider.value_for(:PAGINATION_THEME)
      }

      opts.assert_valid_keys(options.keys)

      options.merge!(opts)

      options[:show_filters] = :no     if options[:show_filters] == false
      options[:show_filters] = :always if options[:show_filters] == true

      rendering = GridRenderer.new(grid, self)

      block.call(rendering) # calling block containing column() calls

      reuse_last_column_for_filter_buttons =
        Defaults::REUSE_LAST_COLUMN_FOR_FILTER_ICONS && rendering.last_column_for_html.capable_of_hosting_filter_related_icons?

      if grid.output_xlsx?
        grid_axlsx(grid, rendering)
      else
        # If blank_slate is defined we don't show any grid at all
        if rendering.blank_slate_handler && grid.resultset.size == 0 && !grid.filtering_on?
          generate_blank_slate(grid, rendering)
        else
          grid_html(grid, options, rendering, reuse_last_column_for_filter_buttons)
        end
      end

      grid.view_helper_finished = true

      grid.axlsx_package
    end

    # Used after <tt>define_grid</tt> to actually output the grid HTML code.
    # Usually used with detached filters: first <tt>define_grid</tt>, then <tt>grid_filter</tt>s, and then
    # <tt>render_grid</tt>
    def render_grid(grid)
      if grid.output_buffer
        grid.output_buffer
      elsif grid.axlsx_package
        grid.axlsx_package
      else
        raise WiceGridException.new("Attempt to use 'render_grid' without 'define_grid' before.")
      end
    end

    def generate_blank_slate(grid, rendering) #:nodoc:
      grid.output_buffer = GridOutputBuffer.new

      grid.output_buffer << if rendering.blank_slate_handler.is_a?(Proc)
                              call_block(rendering.blank_slate_handler, nil)
                            elsif rendering.blank_slate_handler.is_a?(Hash)
                              render(rendering.blank_slate_handler)
                            else
                              rendering.blank_slate_handler
                            end

      # rubocop:disable Style/SymbolProc
      if rendering.find_one_for(:in_html) { |column| column.detach_with_id }
        grid.output_buffer.return_empty_strings_for_nonexistent_filters = true
      end
      # rubocop:enable Style/SymbolProc
    end

    def call_block(block, ar, extra_argument = nil)  #:nodoc:
      extra_argument ? block.call(ar, extra_argument) : block.call(ar)
    end

    def get_row_content(rendering, ar, sorting_dependant_row_cycling) #:nodoc:
      cell_value_of_the_ordered_column = nil
      row_content = ''
      rendering.each_column(:in_html) do |column|
        cell_block = column.cell_rendering_block

        opts = column.html

        opts = opts ? opts.clone : {}

        column_block_output = if column.class == Columns.get_view_column_processor(:action)
                                cell_block.call(ar, params)
                              else
                                call_block(cell_block, ar)
                              end

        if column_block_output.is_a?(Array)

          unless column_block_output.size == 2
            raise WiceGridArgumentError.new('When WiceGrid column block returns an array it is expected to contain 2 elements only - ' \
              'the first is the contents of the table cell and the second is a hash containing HTML attributes for the <td> tag.')
          end

          column_block_output, additional_opts = column_block_output

          unless additional_opts.is_a?(Hash)
            raise WiceGridArgumentError.new('When WiceGrid column block returns an array its second element is expected to be a ' \
                                            "hash containing HTML attributes for the <td> tag. The returned value is #{additional_opts.inspect}. Read documentation.")
          end

          additional_css_class = nil
          if additional_opts.key?(:class)
            additional_css_class = additional_opts[:class]
            additional_opts.delete(:class)
          elsif additional_opts.key?('class')
            additional_css_class = additional_opts['class']
            additional_opts.delete('class')
          end
          opts.merge!(additional_opts)
          Wice::WgHash.add_or_append_class_value!(opts, additional_css_class) unless additional_css_class.blank?
        end

        if sorting_dependant_row_cycling && column.attribute && grid.ordered_by?(column)
          cell_value_of_the_ordered_column = column_block_output
        end
        row_content += content_tag(:td, column_block_output, opts)
      end
      [row_content, cell_value_of_the_ordered_column]
    end

    # the longest method? :(
    def grid_html(grid, options, rendering, reuse_last_column_for_filter_buttons) #:nodoc:
      table_html_attrs, header_tr_html = options[:html], options[:header_tr_html]

      Wice::WgHash.add_or_append_class_value!(table_html_attrs, 'wice-grid', true)

      if Array === Defaults::DEFAULT_TABLE_CLASSES
        Defaults::DEFAULT_TABLE_CLASSES.each do |default_class|
          Wice::WgHash.add_or_append_class_value!(table_html_attrs, default_class, true)
        end
      end

      if options[:class]
        Wice::WgHash.add_or_append_class_value!(table_html_attrs, options[:class])
        options.delete(:class)
      end

      cycle_class = nil
      sorting_dependant_row_cycling = options[:sorting_dependant_row_cycling]

      grid.output_buffer = GridOutputBuffer.new

      # Ruby 1.9.x
      grid.output_buffer.force_encoding('UTF-8') if grid.output_buffer.respond_to?(:force_encoding)

      grid.output_buffer << %(<div class="wice-grid-container table-responsive" data-grid-name="#{grid.name}" id="#{grid.name}"><div id="#{grid.name}_title">)
      grid.output_buffer << content_tag(:h3, grid.saved_query.name) if grid.saved_query
      grid.output_buffer << "</div><table #{public_tag_options(table_html_attrs, true)}>"
      grid.output_buffer << "<caption>#{rendering.kaption}</caption>" if rendering.kaption
      grid.output_buffer << '<thead>'

      no_filters_at_all = (options[:show_filters] == :no || rendering.no_filter_needed?)

      if no_filters_at_all
        no_rightmost_column = no_filter_row = no_filters_at_all
      else
        no_rightmost_column = no_filter_row = (options[:show_filters] == :no || rendering.no_filter_needed_in_main_table?) ? true : false
      end

      no_rightmost_column = true if reuse_last_column_for_filter_buttons

      number_of_columns = rendering.number_of_columns(:in_html)
      number_of_columns -= 1 if no_rightmost_column

      number_of_columns_for_extra_rows = number_of_columns + 1

      pagination_panel_content_html = nil
      if options[:upper_pagination_panel]
        grid.output_buffer << rendering.pagination_panel(number_of_columns, options[:hide_xlsx_button]) do
          pagination_panel_content_html =
            pagination_panel_content(grid, options[:extra_request_parameters], options[:allow_showing_all_records], options[:pagination_theme])
          pagination_panel_content_html
        end
      end

      title_row_attrs = header_tr_html.clone
      Wice::WgHash.add_or_append_class_value!(title_row_attrs, 'wice-grid-title-row', true)

      grid.output_buffer << %(<tr #{public_tag_options(title_row_attrs, true)}>)

      filter_row_id = grid.name + '_filter_row'

      # first row of column labels with sorting links

      filter_shown = if options[:show_filters] == :when_filtered
                       grid.filtering_on?
                     elsif options[:show_filters] == :always
                       true
                     end

      rendering.each_column_aware_of_one_last_one(:in_html) do |column, last|
        column_name = column.name

        opts = column.html

        opts = opts ? opts.clone : {}

        Wice::WgHash.add_or_append_class_value!(opts, column.css_class)

        if column.attribute && (column.ordering || column.sort_by)

          column.add_css_class('active-filter') if grid.filtered_by?(column)

          direction = 'asc'
          link_style = nil
          arrow_class = nil

          if grid.ordered_by?(column)
            column.add_css_class('sorted')
            Wice::WgHash.add_or_append_class_value!(opts, 'sorted')
            link_style = grid.order_direction

            case grid.order_direction
            when 'asc'
              direction = 'desc'
              arrow_class = 'down'
            when 'desc'
              direction = 'asc'
              arrow_class = 'up'
            end
          end

          col_link = link_to(
            (column_name +
              if arrow_class
                ' ' + content_tag(:i, '', class: "fa fa-arrow-#{arrow_class}")
              else
                ''
              end).html_safe,

            rendering.column_link(
              column,
              direction,
              params,
              options[:extra_request_parameters]
            ),
            class: link_style)

          grid.output_buffer << content_tag(:th, col_link, opts)

        else
          if reuse_last_column_for_filter_buttons && last
            grid.output_buffer << content_tag(:th,
                                              hide_show_icon(filter_row_id, grid, filter_shown, no_filter_row, options[:show_filters], rendering), opts
            )
          else
            grid.output_buffer << content_tag(:th, column_name, opts)
          end
        end
      end

      grid.output_buffer << content_tag(:th,
                                        hide_show_icon(filter_row_id, grid, filter_shown, no_filter_row, options[:show_filters], rendering)
      ) unless no_rightmost_column

      grid.output_buffer << '</tr>'
      # rendering first row end

      unless no_filters_at_all # there are filters, we don't know where, in the table or detached
        if no_filter_row # they are all detached
          rendering.each_column(:in_html) do |column|
            if column.filter_shown?
              filter_html_code = column.render_filter.html_safe
              grid.output_buffer.add_filter(column.detach_with_id, filter_html_code)
            end
          end

        else # some filters are present in the table

          filter_row_attrs = header_tr_html.clone
          Wice::WgHash.add_or_append_class_value!(filter_row_attrs, 'wg-filter-row', true)
          filter_row_attrs['id'] = filter_row_id

          grid.output_buffer << %(<tr #{public_tag_options(filter_row_attrs, true)} )
          grid.output_buffer << 'style="display:none"' unless filter_shown
          grid.output_buffer << '>'

          rendering.each_column_aware_of_one_last_one(:in_html) do |column, last|
            opts = column.html ? column.html.clone : {}
            Wice::WgHash.add_or_append_class_value!(opts, column.css_class)

            if column.filter_shown?

              filter_html_code = column.render_filter.html_safe
              if column.detach_with_id
                grid.output_buffer << content_tag(:th, '', opts)
                grid.output_buffer.add_filter(column.detach_with_id, filter_html_code)
              else
                grid.output_buffer << content_tag(:th, filter_html_code, opts)
              end
            else
              if reuse_last_column_for_filter_buttons && last
                grid.output_buffer << content_tag(:th,
                                                  reset_submit_buttons(options, grid, rendering),
                                                  Wice::WgHash.add_or_append_class_value!(opts, 'filter_icons')
                )
              else
                grid.output_buffer << content_tag(:th, '', opts)
              end
            end
          end
          unless no_rightmost_column
            grid.output_buffer << content_tag(:th, reset_submit_buttons(options, grid, rendering), class: 'filter_icons')
          end
          grid.output_buffer << '</tr>'
        end
      end

      grid.output_buffer << '</thead><tfoot>'
      grid.output_buffer << rendering.pagination_panel(number_of_columns, options[:hide_xlsx_button]) do
        if pagination_panel_content_html
          pagination_panel_content_html
        else
          pagination_panel_content_html =
            pagination_panel_content(grid, options[:extra_request_parameters], options[:allow_showing_all_records], options[:pagination_theme])
          pagination_panel_content_html
        end
      end

      grid.output_buffer << '</tfoot><tbody>'

      # rendering  rows
      cell_value_of_the_ordered_column = nil
      previous_cell_value_of_the_ordered_column = nil

      grid.each do |ar| # rows
        before_row_output = if rendering.before_row_handler
                              call_block(rendering.before_row_handler, ar, number_of_columns_for_extra_rows)
                            end

        after_row_output = if rendering.after_row_handler
                             call_block(rendering.after_row_handler, ar, number_of_columns_for_extra_rows)
                           end

        replace_row_output = if rendering.replace_row_handler
                               call_block(rendering.replace_row_handler, ar, number_of_columns_for_extra_rows)
                             end

        row_content = if replace_row_output
                        no_rightmost_column = true
                        replace_row_output
                      else
                        row_content, tmp_cell_value_of_the_ordered_column = get_row_content(rendering, ar, sorting_dependant_row_cycling)
                        cell_value_of_the_ordered_column = tmp_cell_value_of_the_ordered_column if tmp_cell_value_of_the_ordered_column
                        row_content
                      end

        row_attributes = rendering.get_row_attributes(ar)

        if sorting_dependant_row_cycling
          cycle_class = cycle('odd', 'even', name: grid.name) if cell_value_of_the_ordered_column != previous_cell_value_of_the_ordered_column
          previous_cell_value_of_the_ordered_column = cell_value_of_the_ordered_column
        else
          cycle_class = cycle('odd', 'even', name: grid.name)
        end

        Wice::WgHash.add_or_append_class_value!(row_attributes, cycle_class)

        grid.output_buffer << before_row_output if before_row_output
        grid.output_buffer << "<tr #{public_tag_options(row_attributes)}>#{row_content}"
        grid.output_buffer << content_tag(:td, '') unless no_rightmost_column
        grid.output_buffer << '</tr>'
        grid.output_buffer << after_row_output if after_row_output
      end

      last_row_output = if rendering.last_row_handler
                          call_block(rendering.last_row_handler, number_of_columns_for_extra_rows)
                        end

      grid.output_buffer << last_row_output if last_row_output

      grid.output_buffer << '</tbody></table>'

      base_link_for_filter, base_link_for_show_all_records = rendering.base_link_for_filter(controller, options[:extra_request_parameters])

      link_for_export = rendering.link_for_export(controller, 'xlsx', options[:extra_request_parameters])

      parameter_name_for_query_loading = { grid.name => { q: '' } }.to_query
      parameter_name_for_focus = { grid.name => { foc: '' } }.to_query

      processor_initializer_arguments = [
        base_link_for_filter,
        base_link_for_show_all_records,
        link_for_export,
        parameter_name_for_query_loading,
        parameter_name_for_focus,
        Rails.env
      ]

      filter_declarations = if no_filters_at_all
                              []
                            else
                              rendering.select_for(:in_html) do |vc|
                                vc.attribute && vc.filter
                              end.collect(&:yield_declaration)
                            end

      wg_data = {
        'data-processor-initializer-arguments' => processor_initializer_arguments.to_json,
        'data-filter-declarations'             => filter_declarations.to_json,
        :class                                 => 'wg-data'
      }

      wg_data['data-foc'] = grid.status['foc'] if grid.status['foc']

      grid.output_buffer << content_tag(:div, '', wg_data)

      grid.output_buffer << '</div>'

      if Rails.env.development?
        grid.output_buffer << javascript_tag(%/ document.ready = function(){ \n/ +
                                               %$ if (typeof(WiceGridProcessor) == "undefined"){\n$ +
                                               %$   alert("wice_grid.js not loaded, WiceGrid cannot proceed!\\n" +\n$ +
                                               %(     "Make sure that you have loaded wice_grid.js.\\n" + ) +
                                               %(     "Add line //= require wice_grid.js " + ) +
                                               %$     "to app/assets/javascripts/application.js")\n$ +
                                               %( } ) +
                                               %$ } $)
      end

      grid.output_buffer
    end

    def hide_show_icon(_filter_row_id, _grid, filter_shown, no_filter_row, show_filters, _rendering)  #:nodoc:
      no_filter_opening_closing_icon = (show_filters == :always) || no_filter_row

      styles = ['display: block;', 'display: none;']
      styles.reverse! unless filter_shown

      if no_filter_opening_closing_icon
        ''
      else

        content_tag(:div, content_tag(:i, '', class: 'fa fa-eye-slash'),
                    title: NlMessage['hide_filter_tooltip'],
                    style: styles[0],
                    class: 'clickable  wg-hide-filter'
        ) +

          content_tag(:div, content_tag(:i, '', class: 'fa fa-eye'),
                      title: NlMessage['show_filter_tooltip'],
                      style: styles[1],
                      class: 'clickable  wg-show-filter'
          )

      end
    end

    def reset_submit_buttons(options, grid, _rendering)  #:nodoc:
      if options[:hide_submit_button]
        ''
      else
        content_tag(:div, content_tag(:i, '', class: 'fa fa-filter'),
                    title: NlMessage['filter_tooltip'],
                    id:    grid.name + '_submit_grid_icon',
                    class: 'submit clickable'
        )
      end.html_safe + ' ' +
        if options[:hide_reset_button]
          ''
        else

          content_tag(:div, content_tag(:i, '', class: 'fa fa-table'),
                      title: NlMessage['reset_filter_tooltip'],
                      id:    grid.name + '_reset_grid_icon',
                      class: 'reset clickable'
          )
        end.html_safe
    end

    # Renders a detached filter. The parameters are:
    # * +grid+ the WiceGrid object
    # * +filter_key+ an identifier of the filter specified in the column declaration by parameter +:detach_with_id+
    def grid_filter(grid, filter_key)
      unless grid.is_a? WiceGrid
        raise WiceGridArgumentError.new('grid_filter: the parameter must be a WiceGrid instance.')
      end
      if grid.output_buffer.nil?
        raise WiceGridArgumentError.new("grid_filter: You have attempted to run 'grid_filter' before 'grid'. Read about detached filters in the documentation.")
      end
      if grid.output_buffer == true
        raise WiceGridArgumentError.new('grid_filter: You have defined no detached filters, or you try use detached filters with' \
          ':show_filters => :no (set :show_filters to :always in this case). Read about detached filters in the documentation.')
      end

      content_tag :span,
                  grid.output_buffer.filter_for(filter_key),
                  class: "wg-detached-filter #{grid.name}_detached_filter",
                  'data-grid-name' => grid.name
    end

    def grid_axlsx(grid, rendering) #:nodoc:
      spreadsheet = ::Wice::Spreadsheet.new(grid.name)

      # columns
      spreadsheet << rendering.column_labels(:in_xlsx)

      # rendering  rows
      grid.each do |ar| # rows
        row = []

        rendering.each_column(:in_xlsx) do |column|
          cell_block = column.cell_rendering_block

          column_block_output = call_block(cell_block, ar)

          if column_block_output.is_a?(Array)
            column_block_output, _additional_opts = column_block_output
          end

          row << column_block_output
        end
        spreadsheet << row
      end
      grid.axlsx_package = spreadsheet.package
    end

    def pagination_panel_content(grid, extra_request_parameters, allow_showing_all_records, pagination_theme) #:nodoc:
      extra_request_parameters = extra_request_parameters.clone
      if grid.saved_query
        extra_request_parameters["#{grid.name}[q]"] = grid.saved_query.id
      end

      html = pagination_info(grid, allow_showing_all_records)

      paginate(grid.resultset,
               theme:         pagination_theme,
               param_name:    "#{grid.name}[page]",
               params:        extra_request_parameters,
               inner_window:  4,
               outer_window:  2
      ) +
        (' <div class="pagination_status">' + html + '</div>').html_safe
    end

    def show_all_link(collection_total_entries, parameters, _grid_name) #:nodoc:
      message = NlMessage['all_queries_warning']
      confirmation = collection_total_entries > Defaults::START_SHOWING_WARNING_FROM ? message : nil

      html = content_tag(:a, NlMessage['show_all_records_label'],
                         href:  '#',
                         title: NlMessage['show_all_records_tooltip'],
                         class: 'wg-show-all-link',
                         'data-grid-state'     => parameters.to_json,
                         'data-confim-message' => confirmation
      )

      [html, '']
    end

    def back_to_pagination_link(parameters, grid_name) #:nodoc:
      pagination_override_parameter_name = "#{grid_name}[pp]"
      parameters = parameters.reject { |k, _v| k == pagination_override_parameter_name }

      content_tag(:a, NlMessage['switch_back_to_paginated_mode_label'],
                  href:   '#',
                  title:  NlMessage['switch_back_to_paginated_mode_tooltip'],
                  class:  'wg-back-to-pagination-link',
                  'data-grid-state' => parameters.to_json
      )
    end

    def pagination_info(grid, allow_showing_all_records)  #:nodoc:
      collection = grid.resultset

      if grid.all_record_mode?

        collection_total_entries = collection.length

        first = 1
        last = collection.size

        total_pages = 1

        class << collection
          def current_page
            1
          end

          def total_pages
            1
          end
        end

      else
        collection_total_entries = collection.total_count

        first = collection.offset_value + 1
        last  = collection.last_page? ? collection.total_count : collection.offset_value + collection.limit_value

        total_pages = collection.total_pages
      end

      parameters = grid.get_state_as_parameter_value_pairs

      if total_pages < 2 && collection.length == 0
        '0'
      else
        parameters << ["#{grid.name}[pp]", collection_total_entries]

        show_all_records_link = allow_showing_all_records && collection_total_entries > collection.length

        if show_all_records_link && limit = Wice::ConfigurationProvider.value_for(:SHOW_ALL_ALLOWED_UP_TO, strict: false)
          show_all_records_link = limit > collection_total_entries
        end

        "#{first}-#{last} / #{collection_total_entries} " +
          if show_all_records_link
            res, _js = show_all_link(collection_total_entries, parameters, grid.name)
            res
          else
            ''
          end
      end +
        if grid.all_record_mode?
          back_to_pagination_link(parameters, grid.name)
        else
          ''
        end
    end
  end
end
