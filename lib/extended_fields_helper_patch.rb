require_dependency 'custom_fields_helper'

module ExtendedFieldsHelperPatch

    def self.included(base)
        if Redmine::VERSION::MAJOR > 2 || (Redmine::VERSION::MAJOR == 2 && Redmine::VERSION::MINOR >= 5)
            base.send(:include, InstanceMethods)
        else
            base.send(:include, ObsoleteMethods)
        end
        base.class_eval do
            unloadable

            alias_method       :show_value,                     :show_extended_value
            alias_method_chain :custom_field_tag,               :extended
            alias_method_chain :custom_field_tag_for_bulk_edit, :extended
        end
    end

    module InstanceMethods

        def show_extended_value(custom_value, html = true)
            if custom_value.value && !custom_value.value.empty? &&
               (template = find_custom_field_template(custom_value.custom_field))
                render(:partial => template,
                       :locals  => { :controller   => controller,
                                     :project      => @project,
                                     :request      => request,
                                     :custom_field => custom_value,
                                     :html         => html })
            else
                format_object(custom_value, html)
            end
        end

        def custom_field_tag_with_extended(prefix, custom_value)
            custom_field = custom_value.custom_field

            tag = custom_field_tag_without_extended(prefix, custom_value)

            unless custom_field.hint.blank?
                tag << tag(:br)
                tag << content_tag(:em, h(custom_field.hint))
            end

            if (template = find_custom_field_edit_template(custom_field))
                tag << render(:partial => template,
                              :locals  => { :controller   => controller,
                                            :project      => @project,
                                            :request      => request,
                                            :custom_field => custom_value,
                                            :name         => name,
                                            :field_name   => field_name,
                                            :field_id     => field_id })
            end

            tag
        end

        def custom_field_tag_for_bulk_edit_with_extended(prefix, custom_field, objects = nil, value = '')
            tag = custom_field_tag_for_bulk_edit_without_extended(prefix, custom_field, objects, value)

            unless custom_field.hint.blank?
                tag << tag(:br)
                tag << content_tag(:em, h(custom_field.hint))
            end

            if (template = find_custom_field_edit_template(custom_field))
                tag << render(:partial => template,
                              :locals  => { :controller   => controller,
                                            :project      => @project,
                                            :request      => request,
                                            :custom_field => custom_value,
                                            :name         => name,
                                            :field_name   => field_name,
                                            :field_id     => field_id })
            end

            tag
        end

    end

    module ObsoleteMethods

        def show_extended_value(custom_value)
            if custom_value
                begin
                    format = params[:format]
                rescue NoMethodError
                    format = nil
                end
                if custom_value.value && !custom_value.value.empty? && format.nil? &&
                   (template = find_custom_field_template(custom_value.custom_field))
                    safe_buffer = (defined? ActiveSupport::SafeBuffer) ? ActiveSupport::SafeBuffer : ActionView::SafeBuffer
                    safe_buffer.new(render(:partial => template,
                                           :locals  => { :controller   => controller,
                                                         :project      => @project,
                                                         :request      => request,
                                                         :custom_field => custom_value }))
                else
                    if respond_to?(:format_value)
                        format_value(custom_value.value, custom_value.custom_field.field_format)
                    else # Redmine < 2.2.x
                        Redmine::CustomFieldFormat.format_value(custom_value.value, custom_value.custom_field.field_format)
                    end
                end
            end
        end

        def custom_field_tag_with_extended(name, custom_value)
            custom_field = custom_value.custom_field
            field_name   = "#{name}[custom_field_values][#{custom_field.id}]"
            field_id     = "#{name}_custom_field_values_#{custom_field.id}"
            field_title  = custom_field.name.gsub(%r{[^a-z0-9_]+}i, '_').downcase
            field_class  = (field_title =~ %r{[a-z0-9]+}i) ? "#{name}_custom_field_values_#{field_title}" : field_id
            field_format = Redmine::CustomFieldFormat.find_by_name(custom_field.field_format)

            case field_format.try(:edit_as)
            when 'string', 'link'
                tag = text_field_tag(field_name, custom_value.value, :id => field_id, :class => field_class)
            when 'anyuser'
                tag =  text_field_tag "cf_#{field_id}_search_ac", nil
                tag << link_to_function(l(:label_cancel), "$('#cf_#{field_id}_search_ac').val(''); $('##{field_id}').html($('##{field_id}_cancel_content').html()); $('##{field_id}').attr('size', 1); return false;")
                tag << tag(:br)

                blank = custom_field.is_required? ?
                      ((custom_field.default_value.blank? && custom_value.value.blank?) ? content_tag(:option, "--- #{l(:actionview_instancetag_blank_option)} ---") : ''.html_safe) :
                        content_tag(:option)

                select_tag_content = blank + options_for_select(custom_field.possible_values_options(custom_value.customized), custom_value.value)

                tag << select_tag(field_name, select_tag_content, :id => field_id, :class => field_class)
                tag << content_tag(:span,  select_tag_content, id: "#{field_id}_cancel_content", style: 'display:none')

                tag << javascript_tag("
                         observeSearchfield('cf_#{field_id}_search_ac', '#{field_id}',
                             '#{
                                     escape_javascript url_for(
                                             :controller     => @issue.id.nil? ? 'projects'  : 'issues',
                                             :action         => 'extended_fields_autocomplete_for_user',
                                             :id             => @issue.id.nil? ? @project.identifier : @issue.id,
                                             :selected       => custom_value.value,
                                             :field_id       => field_id
                                     )
                               }'
                         )
                     ")
            when 'project'
                blank = custom_field.is_required? ?
                      ((custom_field.default_value.blank? && custom_value.value.blank?) ? content_tag(:option, "--- #{l(:actionview_instancetag_blank_option)} ---") : ''.html_safe) :
                        content_tag(:option)
                tag = select_tag(field_name,
                                 blank + options_for_select(custom_field.possible_values_options(custom_value.customized), custom_value.value),
                                 :id => field_id, :class => field_class)
            else
                tag = custom_field_tag_without_extended(name, custom_value)
            end

            unless custom_field.hint.blank?
                tag << tag(:br)
                tag << content_tag(:em, h(custom_field.hint))
            end

            template = find_custom_field_edit_template(custom_field)
            if template
                tag << render(:partial => template,
                              :locals  => { :controller   => controller,
                                            :project      => @project,
                                            :request      => request,
                                            :custom_field => custom_value,
                                            :name         => name,
                                            :field_name   => field_name,
                                            :field_id     => field_id })
            end

            tag
        end

        def custom_field_tag_for_bulk_edit_with_extended(name, custom_field, projects = nil)
            field_name = "#{name}[custom_field_values][#{custom_field.id}]"
            field_name << "[]" if custom_field.respond_to?(:multiple?) && custom_field.multiple?
            field_id   = "#{name}_custom_field_values_#{custom_field.id}"
            field_title  = custom_field.name.gsub(%r{[^a-z0-9_]+}i, '_').downcase
            field_class  = (field_title =~ %r{[a-z0-9]+}i) ? "#{name}_custom_field_values_#{field_title}" : field_id
            field_format = Redmine::CustomFieldFormat.find_by_name(custom_field.field_format)

            case field_format.try(:edit_as)
            when 'string', 'link'
                tag = text_field_tag(field_name, '', :id => field_id, :class => field_class)
            when 'project'
                tag = select_tag(field_name,
                                 options_for_select([ [ l(:label_no_change_option), '' ] ] + custom_field.possible_values_options(projects)),
                                 :id => field_id, :class => field_class)
            else
                tag = custom_field_tag_for_bulk_edit_without_extended(name, custom_field, projects)
            end

            unless custom_field.hint.blank?
                tag << tag(:br)
                tag << content_tag(:em, h(custom_field.hint))
            end

            template = find_custom_field_edit_template(custom_field)
            if template
                tag << render(:partial => template,
                              :locals  => { :controller   => controller,
                                            :project      => @project,
                                            :request      => request,
                                            :custom_field => custom_value,
                                            :name         => name,
                                            :field_name   => field_name,
                                            :field_id     => field_id })
            end

            tag
        end

    end

end
