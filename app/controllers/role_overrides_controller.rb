#
# Copyright (C) 2011 Instructure, Inc.
#
# This file is part of Canvas.
#
# Canvas is free software: you can redistribute it and/or modify it under
# the terms of the GNU Affero General Public License as published by the Free
# Software Foundation, version 3 of the License.
#
# Canvas is distributed in the hope that it will be useful, but WITHOUT ANY
# WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR
# A PARTICULAR PURPOSE. See the GNU Affero General Public License for more
# details.
#
# You should have received a copy of the GNU Affero General Public License along
# with this program. If not, see <http://www.gnu.org/licenses/>.
#

# @API Roles
# API for managing account- and course-level roles, and their associated permissions.
#
# @object Role
#   {
#     // The label and unique identifier of the role.
#     "role": "New Role",
#
#     // The role type that is being used as a base for this role.
#     // For account-level roles, this is "AccountMembership".
#     // For course-level roles, it is an enrollment type.
#     "base_role_type": "AccountMembership"
#
#     // JSON representation of the account the role is in.
#     "account": {
#       "id": 1019,
#       "name": "CGNU",
#       "parent_account_id": 73,
#       "root_account_id": 1,
#       "sis_account_id": "cgnu"
#     },
#
#     // The state of the role: "active" or "inactive"
#     "workflow_state": "active",
#
#     // A dictionary of permissions keyed by name (see permissions input
#     // parameter in the "Create a role" API). The value for a given permission
#     // is a dictionary of the following boolean flags:
#     // - enabled:  Whether the role has the permission.
#     // - locked: Whether the permission is locked by this role.
#     // - readonly: Whether the permission can be modified in this role (i.e.
#     //     whether the permission is locked by an upstream role).
#     // - explicit: Whether the value of enabled is specified explicitly by
#     //     this role, or inherited from an upstream role.
#     // - prior_default: The value that would have been inherited from upstream
#     //     if the role had not explicitly set a value. Only present if explicit
#     //     is true.
#     "permissions": {
#       "read_course_content": {
#         "enabled": true,
#         "locked": false,
#         "readonly": false,
#         "explicit": true,
#         "prior_default": false
#       },
#       "read_course_list": {
#         "enabled": true,
#         "locked": true,
#         "readonly": true,
#         "explicit": false
#       },
#       "read_question_banks": {
#         "enabled": false,
#         "locked": true,
#         "readonly": false,
#         "explicit": true,
#         "prior_default": false
#       },
#       "read_reports": {
#         "enabled": true,
#         "locked": false,
#         "readonly": false,
#         "explicit": false
#       },
#       ...
#     }
#   }
#
class RoleOverridesController < ApplicationController
  before_filter :require_context
  before_filter :require_role, :only => [:activate_role, :add_role, :remove_role, :update, :show]

  # @API List roles
  # List the roles available to an account.
  #
  # @argument account_id The id of the account to retrieve roles for.
  # @argument state[] Filter by role state. Accepted values are 'active' and 'inactive'. If this argument
  #   is omitted, only 'active' roles are returned.
  #
  # @returns [Role]
  def api_index
    if authorized_action(@context, @current_user, :manage_role_overrides)
      route = polymorphic_url([:api, :v1, @context, :roles])
      states = params[:state].to_a.reject{ |s| %w(active inactive).exclude?(s) }
      states = %w(active) if states.empty?
      roles = []
      roles += Role.built_in_roles if states.include?('active')
      roles += @context.roles.scoped(:conditions => {:workflow_state => states}, :order => :id).all
      roles = Api.paginate(roles, self, route)
      render :json => roles.collect{|role| role_json(@context, role, @current_user, session)}
    end
  end

  def index
    if authorized_action(@context, @current_user, :manage_role_overrides)
      @managing_account_roles = @context.is_a?(Account) && (params[:account_roles] || @context.site_admin?)

      if @managing_account_roles
        @role_types = RoleOverride.account_membership_types(@context)
      else
        @role_types = RoleOverride.enrollment_types
      end

      respond_to do |format|
        format.html
      end
    end
  end

  # @API Get a single role
  # Retrieve information about a single role
  #
  # @argument account_id The id of the account containing the role
  # @argument role The name and unique identifier for the role
  #
  # @returns Role
  def show
    if authorized_action(@context, @current_user, :manage_role_overrides)
      role = @context.find_role(@role)
      role ||= Role.built_in_role(@role)
      raise ActiveRecord::RecordNotFound unless role
      render :json => role_json(@context, role, @current_user, session)
    end
  end

  include Api::V1::Role

  # @API Create a new role
  # Create a new course-level or account-level role.
  #
  # @argument role
  #   Label and unique identifier for the role.
  #
  # @argument base_role_type [Optional] Accepted values are 'AccountMembership', 'StudentEnrollment', 'TeacherEnrollment', 'TaEnrollment', 'ObserverEnrollment', and 'DesignerEnrollment'
  #   Specifies the role type that will be used as a base
  #   for the permissions granted to this role.
  #
  #   Defaults to 'AccountMembership' if absent
  #
  # @argument permissions[<X>][explicit] [Optional]
  # @argument permissions[<X>][enabled] [Optional]
  #   If explicit is 1 and enabled is 1, permission <X> will be explicitly
  #   granted to this role. If explicit is 1 and enabled has any other value
  #   (typically 0), permission <X> will be explicitly denied to this role. If
  #   explicit is any other value (typically 0) or absent, or if enabled is
  #   absent, the value for permission <X> will be inherited from upstream.
  #   Ignored if permission <X> is locked upstream (in an ancestor account).
  #
  #   May occur multiple times with unique values for <X>. Recognized
  #   permission names for <X> are:
  #
  #     [For Account-Level Roles Only]
  #     become_user                      -- Become other users
  #     manage_account_memberships       -- Add/remove other admins for the account
  #     manage_account_settings          -- Manage account-level settings
  #     manage_alerts                    -- Manage global alerts
  #     manage_courses                   -- Manage ( add / edit / delete ) courses
  #     manage_developer_keys            -- Manage developer keys
  #     manage_global_outcomes           -- Manage learning outcomes
  #     manage_jobs                      -- Manage background jobs
  #     manage_role_overrides            -- Manage permissions
  #     manage_sis                       -- Import and manage SIS data
  #     manage_site_settings             -- Manage site-wide and plugin settings
  #     manage_user_logins               -- Modify login details for users
  #     read_course_content              -- View course content
  #     read_course_list                 -- View the list of courses
  #     read_messages                    -- View notifications sent to users
  #     site_admin                       -- Use the Site Admin section and admin all other accounts
  #     view_error_reports               -- View error reports
  #     view_statistics                  -- View statistics
  #
  #     [For both Account-Level and Course-Level roles]
  #      Note: Applicable enrollment types for course-level roles are given in brackets:
  #            S = student, T = teacher, A = TA, D = designer, O = observer.
  #            Lower-case letters indicate permissions that are off by default.
  #            A missing letter indicates the permission cannot be enabled for the role
  #            or any derived custom roles.
  #     change_course_state              -- [ TaD ] Change course state
  #     comment_on_others_submissions    -- [sTAD ] View all students' submissions and make comments on them
  #     create_collaborations            -- [STADo] Create student collaborations
  #     create_conferences               -- [STADo] Create web conferences
  #     manage_admin_users               -- [ Tad ] Add/remove other teachers, course designers or TAs to the course
  #     manage_assignments               -- [ TADo] Manage (add / edit / delete) assignments and quizzes
  #     manage_calendar                  -- [sTADo] Add, edit and delete events on the course calendar
  #     manage_content                   -- [ TADo] Manage all other course content
  #     manage_files                     -- [ TADo] Manage (add / edit / delete) course files
  #     manage_grades                    -- [ TA  ] Edit grades (includes assessing rubrics)
  #     manage_groups                    -- [ TAD ] Manage (create / edit / delete) groups
  #     manage_interaction_alerts        -- [ Ta  ] Manage alerts
  #     manage_outcomes                  -- [sTaDo] Manage learning outcomes
  #     manage_sections                  -- [ TaD ] Manage (create / edit / delete) course sections
  #     manage_students                  -- [ TAD ] Add/remove students for the course
  #     manage_user_notes                -- [ TA  ] Manage faculty journal entries
  #     manage_wiki                      -- [ TADo] Manage wiki (add / edit / delete pages)
  #     read_forum                       -- [STADO] View discussions
  #     moderate_forum                   -- [sTADo] Moderate discussions (delete/edit others' posts, lock topics)
  #     post_to_forum                    -- [STADo] Post to discussions
  #     read_question_banks              -- [ TADo] View and link to question banks
  #     read_reports                     -- [sTAD ] View usage reports for the course
  #     read_roster                      -- [STADo] See the list of users
  #     read_sis                         -- [sTa  ] Read SIS data
  #     send_messages                    -- [STADo] Send messages to course members
  #     view_all_grades                  -- [ TAd ] View all grades
  #     view_group_pages                 -- [sTADo] View the group pages of all student groups
  #
  #   Some of these permissions are applicable only for roles on the site admin
  #   account, on a root account, or for course-level roles with a particular base role type;
  #   if a specified permission is inapplicable, it will be ignored.
  #
  #   Additional permissions may exist based on installed plugins.
  #
  # @argument permissions[<X>][locked] [Optional]
  #   If the value is 1, permission <X> will be locked downstream (new roles in
  #   subaccounts cannot override the setting). For any other value, permission
  #   <X> is left unlocked. Ignored if permission <X> is already locked
  #   upstream. May occur multiple times with unique values for <X>.
  #
  # @example_request
  #   curl 'http://<canvas>/api/v1/accounts/<account_id>/roles.json' \
  #        -H "Authorization: Bearer <token>" \ 
  #        -F 'role=New Role' \ 
  #        -F 'permissions[read_course_content][explicit]=1' \ 
  #        -F 'permissions[read_course_content][enabled]=1' \ 
  #        -F 'permissions[read_course_list][locked]=1' \ 
  #        -F 'permissions[read_question_banks][explicit]=1' \ 
  #        -F 'permissions[read_question_banks][enabled]=0' \ 
  #        -F 'permissions[read_question_banks][locked]=1'
  #
  # @returns Role
  def add_role
    return unless authorized_action(@context, @current_user, :manage_role_overrides)

    if @context.has_role?(@role)
      if api_request?
        render :json => {:message => "role already exists"}, :status => :bad_request
      else
        flash[:error] = t(:update_failed_notice, 'Role creation failed')
        redirect_to named_context_url(@context, :context_permissions_url, :account_roles => params[:account_roles])
      end
      return
    end

    base_role_type = params[:base_role_type] || AccountUser::BASE_ROLE_NAME
    role = @context.roles.deleted.find_by_name(@role)
    role ||= @context.roles.build(:name => @role)
    role.base_role_type = base_role_type
    role.workflow_state = 'active'
    role.deleted_at = nil
    if !role.save
      render :json => { :message => role.errors.full_messages.to_sentence }, :status => :bad_request
      return
    end
    # remove old role overrides that were associated with this role name
    @context.role_overrides.scoped(:conditions => {:enrollment_type => @role}).delete_all

    unless api_request?
      redirect_to named_context_url(@context, :context_permissions_url, :account_roles => params[:account_roles])
      return
    end

    # allow setting permissions immediately through API
    set_permissions_for(@role, @context, params[:permissions])

    render :json => role_json(@context, role, @current_user, session)
  end

  # @API Deactivate a role
  # Deactivates a custom role.  This hides it in the user interface and prevents it
  # from being assigned to new users.  Existing users assigned to the role will
  # continue to function with the same permissions they had previously.
  # Built-in roles cannot be deactivated.
  #
  # @argument role
  #   Label and unique identifier for the role.
  #
  # @returns Role
  def remove_role
    if authorized_action(@context, @current_user, :manage_role_overrides)
      role = @context.roles.not_deleted.find_by_name!(@role)
      role.deactivate!
      respond_to do |format|
        format.html { redirect_to named_context_url(@context, :context_permissions_url, :account_roles => params[:account_roles]) }
        format.json { render :json => role_json(@context, role, @current_user, session) }
      end
    end
  end

  # @API Activate a role
  # Re-activates an inactive role (allowing it to be assigned to new users)
  #
  # @argument role
  #   Label and unique identifier for the role.
  #
  # @returns Role
  def activate_role
    if authorized_action(@context, @current_user, :manage_role_overrides)
      if course_role = @context.roles.inactive.find_by_name(@role)
        course_role.activate!
        render :json => role_json(@context, course_role, @current_user, session)
      else
        render :json => {:message => t('no_role_found', "Role not found")}, :status => :bad_request
      end
    end
  end

  # @API Update a role
  # Update permissions for an existing role.
  #
  # Recognized roles are:
  # * TeacherEnrollment
  # * StudentEnrollment
  # * TaEnrollment
  # * ObserverEnrollment
  # * DesignerEnrollment
  # * AccountAdmin
  # * Any previously created custom role
  #
  # @argument permissions[<X>][explicit] [Optional]
  # @argument permissions[<X>][enabled] [Optional]
  #   These arguments are described in the documentation for the {api:RoleOverridesController#add_role add_role method}.
  #
  # @example_request
  #   curl https://<canvas>/api/v1/accounts/:account_id/roles/TaEnrollment \ 
  #     -X PUT \ 
  #     -H 'Authorization: Bearer <access_token>' \ 
  #     -F 'permissions[manage_groups][explicit]=1' \ 
  #     -F 'permissions[manage_groups][enabled]=1' \ 
  #     -F 'permissions[manage_groups][locked]=1' \ 
  #     -F 'permissions[send_messages][explicit]=1' \ 
  #     -F 'permissions[send_messages][enabled]=0'
  #
  # @returns Role
  def update
    return unless authorized_action(@context, @current_user, :manage_role_overrides)
    role = Role.built_in_role(@role) || @context.find_role(@role)
    raise ActiveRecord::RecordNotFound unless role
    set_permissions_for(@role, @context, params[:permissions])
    RoleOverride.clear_cached_contexts
    render :json => role_json(@context, role, @current_user, session)
  end

  def create
    if authorized_action(@context, @current_user, :manage_role_overrides)
      @role_types = RoleOverride.enrollment_types
      @role_types = RoleOverride.account_membership_types(@context) if @context.is_a?(Account) && (params[:account_roles] || @context == Account.site_admin)
      if params[:permissions]
        RoleOverride.permissions.keys.each do |key|
          if params[:permissions][key]
            @role_types.each do |enrollment_type|
              role = enrollment_type[:name]
              if settings = params[:permissions][key][role]
                override = settings[:override] == 'checked' if ['checked', 'unchecked'].include?(settings[:override])
                locked = settings[:locked] == 'true' if settings[:locked]
                RoleOverride.manage_role_override(@context, role, key.to_s, :override => override, :locked => locked)
              end
            end
          end
        end
      end
      flash[:notice] = t 'notices.saved', "Changes Saved Successfully."
      redirect_to named_context_url(@context, :context_permissions_url, :account_roles => params[:account_roles])
    end
  end

  # Internal: Get role from params or return error. Used as before filter.
  #
  # Returns found role or false (to halt execution).
  def require_role
    @role = api_request? ? params[:role] : params[:role_type]
    @role ||= params[:role]
    unless @role.present?
      if api_request?
        render :json => {
          :message => "missing required parameter 'role'" },
          :status => :bad_request
      else
        flash[:error] = t(:update_failed_notice, 'Role creation failed')
        redirect_to named_context_url(@context, :context_permissions_url,
          :account_roles => params[:account_roles])
      end

      return false
    end

    @role
  end
  protected :require_role

  # Internal: Loop through and set permission on role given in params.
  #
  # role - The role to set permissions for.
  # context - The current context.
  # permissions - The permissions from the request params.
  #
  # Returns nothing.
  def set_permissions_for(role, context, permissions)
    return unless permissions.present?

    if course_role = context.roles.active.find_by_name(role)
      manageable_permissions = RoleOverride.manageable_permissions(context, course_role.base_role_type)
    else
      manageable_permissions = RoleOverride.manageable_permissions(context)
    end

    manageable_permissions.keys.each do |permission|
      if settings = permissions[permission]
        if settings.has_key?(:enabled) && value_to_boolean(settings[:explicit])
          override = value_to_boolean(settings[:enabled])
        end
        locked = value_to_boolean(settings[:locked]) if settings.has_key?(:locked)

        RoleOverride.manage_role_override(context, role, permission.to_s,
          :override => override, :locked => locked)
      end
    end
  end
  protected :set_permissions_for
end
