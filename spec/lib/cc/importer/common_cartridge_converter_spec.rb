require File.dirname(__FILE__) + '/../cc_spec_helper'

describe "Standard Common Cartridge importing" do
  before(:all) do
    archive_file_path = File.join(File.dirname(__FILE__) + "/../../../fixtures/migration/cc_full_test.zip")
    unzipped_file_path = File.join(File.dirname(archive_file_path), "cc_#{File.basename(archive_file_path, '.zip')}", 'oi')
    @export_folder = File.join(File.dirname(archive_file_path), "cc_cc_full_test")
    @converter = CC::Importer::Standard::Converter.new(:export_archive_path=>archive_file_path, :course_name=>'oi', :base_download_dir=>unzipped_file_path)
    @converter.export
    @course_data = @converter.course.with_indifferent_access
    @course_data['all_files_export'] ||= {}
    @course_data['all_files_export']['file_path'] = @course_data['all_files_zip']
  end
  
  after(:all) do
    @converter.delete_unzipped_archive
    if File.exists?(@export_folder)
      FileUtils::rm_rf(@export_folder)
    end
  end

  before(:each) do
    @course = course
    @migration = ContentMigration.create(:context => @course)
    @migration.migration_settings[:migration_ids_to_import] = {:copy => {}}
    @course.import_from_migration(@course_data, nil, @migration)
  end

  it "should import webcontent" do
    @course.attachments.count.should == 10
    atts = %w{I_00001_R I_00006_Media I_media_R f3 f4 f5 8612e3db71e452d5d2952ff64647c0d8 I_00003_R_IMAGERESOURCE 7acb90d1653008e73753aa2cafb16298 6a35b0974f59819404dc86d48fe39fc3}
    atts.each do |mig_id|
      @course.attachments.find_by_migration_id(mig_id).should_not be_nil
    end
  end
  
  it "should import discussion topics" do
    @course.discussion_topics.count.should == 2
    file1_id = @course.attachments.find_by_migration_id("I_media_R").id
    file2_id = @course.attachments.find_by_migration_id("I_00006_Media").id
    
    dt =  @course.discussion_topics.find_by_migration_id("I_00006_R")
    dt.message.should == %{<p>Your face is ugly. <br><img src="/courses/#{@course.id}/files/#{file1_id}/preview"></p>}
    dt.attachment_id = file2_id
    
    dt =  @course.discussion_topics.find_by_migration_id("I_00009_R")
    dt.message.should == %{<p>Monkeys: Go!</p>\n<ul>\n<li>\n<a href="/courses/#{@course.id}/files/#{file2_id}/preview">angry_person.jpg</a>\n</li>\n<li>\n<a href="/courses/#{@course.id}/files/#{file1_id}/preview">smiling_dog.jpg</a>\n</li>\n</ul>} 
  end

  # This also tests the WebLinks, they are just content tags and don't have their own class
  it "should import modules from organization" do
    @course.context_modules.count.should == 3
    
    mod1 = @course.context_modules.find_by_migration_id("I_00000")
    mod1.name.should == "Your Mom, Research, & You"
    tag = mod1.content_tags[0]
    tag.content_type.should == 'Attachment'
    tag.content_id.should == @course.attachments.find_by_migration_id("I_00001_R").id
    tag.indent.should == 0
    tag = mod1.content_tags[1]
    tag.content_type.should == 'ContextModuleSubHeader'
    tag.title.should == "Study Guide"
    tag.indent.should == 0
    index = 2
    if Qti.qti_enabled?
      tag = mod1.content_tags[index]
      tag.title.should == "Pretest"
      tag.content_type.should == 'Quiz'
      tag.content_id.should == @course.quizzes.find_by_migration_id("I_00003_R").id
      tag.indent.should == 1
      index += 1
    end
    tag = mod1.content_tags[index]
    tag.content_type.should == 'ExternalUrl'
    tag.title.should == "Wikipedia - Your Mom"
    tag.url.should == "http://en.wikipedia.org/wiki/Maternal_insult"
    tag.indent.should == 0
    
    mod1 = @course.context_modules.find_by_migration_id("m2")
    mod1.name.should == "Attachment module"
    mod1.content_tags.count.should == 5
    tag = mod1.content_tags[0]
    tag.content_type.should == 'Attachment'
    tag.content_id.should == @course.attachments.find_by_migration_id("f3").id
    tag.indent.should == 0
    tag = mod1.content_tags[1]
    tag.content_type.should == 'ContextModuleSubHeader'
    tag.title.should == "Sub-Folder"
    tag.indent.should == 0
      tag = mod1.content_tags[2]
      tag.content_type.should == 'Attachment'
      tag.content_id.should == @course.attachments.find_by_migration_id("f4").id
      tag.indent.should == 1
      tag = mod1.content_tags[3]
      tag.content_type.should == 'ContextModuleSubHeader'
      tag.title.should == "Sub-Folder 2"
      tag.indent.should == 1
        tag = mod1.content_tags[4]
        tag.content_type.should == 'Attachment'
        tag.content_id.should == @course.attachments.find_by_migration_id("f5").id
        tag.indent.should == 2
    
    mod1 = @course.context_modules.find_by_migration_id("m3")
    mod1.name.should == "Misc Module"
    mod1.content_tags.count.should == 4
    tag = mod1.content_tags[0]
    tag.content_type.should == 'ExternalUrl'
    tag.title.should == "Wikipedia - Sigmund Freud"
    tag.url.should == "http://en.wikipedia.org/wiki/Sigmund_Freud"
    tag.indent.should == 0
    tag = mod1.content_tags[1]
    tag.content_type.should == 'DiscussionTopic'
    tag.title.should == "Talk about the issues"
    tag.content_id.should == @course.discussion_topics.find_by_migration_id("I_00009_R").id
    tag.indent.should == 0
    tag = mod1.content_tags[2]
    tag.content_type.should == 'ContextExternalTool'
    tag.title.should == "BLTI Test"
    tag.url.should == "http://www.imsglobal.org/developers/BLTI/tool.php"
    tag.indent.should == 0
    tag = mod1.content_tags[3]
    tag.content_type.should == 'Assignment'
    tag.title.should == "BLTI Assignment Test"
    tag.content_id.should == @course.assignments.find_by_migration_id("I_00011_R").id
    tag.indent.should == 0
  end
  
  it "should import external tools" do
    @course.context_external_tools.count.should == 2
    et = @course.context_external_tools.find_by_migration_id("I_00010_R")
    et.name.should == "BLTI Test"
    et.url.should == 'http://www.imsglobal.org/developers/BLTI/tool.php'
    et.settings[:custom_fields].should == {"key1"=>"value1", "key2"=>"value2"}
    et.settings[:vendor_extensions].should == [{:platform=>"my.lms.com", :custom_fields=>{"key"=>"value"}}, {:platform=>"your.lms.com", :custom_fields=>{"key"=>"value", "key2"=>"value2"}}].map(&:with_indifferent_access)
    @migration.warnings.member?("The security parameters for the external tool \"#{et.name}\" need to be set in Course Settings.").should be_true

    et = @course.context_external_tools.find_by_migration_id("I_00011_R")
    et.name.should == "BLTI Assignment Test"
    et.url.should == 'http://www.imsglobal.org/developers/BLTI/tool2.php'
    et.settings[:custom_fields].should == {}
    et.settings[:vendor_extensions].should == [].map(&:with_indifferent_access)
    @migration.warnings.member?("The security parameters for the external tool \"#{et.name}\" need to be set in Course Settings.").should be_true

    # That second tool had the assignment flag set, so an assignment for it should have been created
    asmnt = @course.assignments.find_by_migration_id("I_00011_R")
    asmnt.should_not be_nil
    asmnt.points_possible.should == 15.5
    asmnt.external_tool_tag.url.should == et.url
    asmnt.external_tool_tag.content_type.should == 'ContextExternalTool'
  end

  it "should import assessment data" do
    if Qti.qti_enabled?
      quiz = @course.quizzes.find_by_migration_id("I_00003_R")
      quiz.quiz_questions.count.should == 11
      quiz.title.should == "Pretest"
      quiz.quiz_type.should == 'assignment'
      quiz.allowed_attempts.should == 2
      quiz.time_limit.should == 120

      question = quiz.quiz_questions.first
      question.question_data[:points_possible].should == 2

      bank = @course.assessment_question_banks.find_by_migration_id("I_00004_R_QDB_1")
      bank.assessment_questions.count.should == 11
      bank.title.should == "QDB_1"
    else
      pending("Can't import assessment data with python QTI tool.")
    end
  end

  it "should find update urls in questions" do
    if Qti.qti_enabled?
      q = @course.assessment_questions.find_by_migration_id("I_00003_R_QUE_104045")

      q.question_data[:question_text].should =~ %r{/assessment_questions/#{q.id}/files/\d+/}
      q.question_data[:answers].first[:html].should =~ %r{/assessment_questions/#{q.id}/files/\d+/}
      q.question_data[:answers].first[:comments_html].should =~ %r{/assessment_questions/#{q.id}/files/\d+/}
    else
      pending("Can't import assessment data with python QTI tool.")
    end
  end
  
  context "re-importing the cartridge" do
    
    append_before do
      @migration2 = ContentMigration.create(:context => @course)
      @migration2.migration_settings[:migration_ids_to_import] = {:copy=>{}}
      @course.import_from_migration(@course_data, nil, @migration2)
    end
    
    it "should import webcontent" do
      @course.attachments.count.should == 20
      @course.attachments.active.count.should == 10
      mig_ids = %w{I_00001_R I_00006_Media I_media_R f3 f4 f5 8612e3db71e452d5d2952ff64647c0d8 I_00003_R_IMAGERESOURCE 7acb90d1653008e73753aa2cafb16298 6a35b0974f59819404dc86d48fe39fc3}
      mig_ids.each do |mig_id|
        atts = @course.attachments.find_all_by_migration_id(mig_id)
        atts.length.should == 2
        atts.any?{|a|a.file_state = 'deleted'}.should == true
        atts.any?{|a|a.file_state = 'available'}.should == true
      end
    end
    
    it "should point to new attachment from module" do
      @course.context_modules.count.should == 3
      
      mod1 = @course.context_modules.find_by_migration_id("I_00000")
      mod1.content_tags.active.count.should == (Qti.qti_enabled? ? 5 : 4)
      mod1.name.should == "Your Mom, Research, & You"
      tag = mod1.content_tags.active[0]
      tag.content_type.should == 'Attachment'
      tag.content_id.should == @course.attachments.active.find_by_migration_id("I_00001_R").id
      puts mod1.content_tags.active.count
    end
  end

  context "selective import" do
    before(:each) do
      @course = course
      @migration = ContentMigration.create(:context => @course)
      @migration.migration_settings[:migration_ids_to_import] = {
              :copy => {"topics" => {"I_00006_R" => true},
                        "everything" => "0",
                        "folders" =>
                                {"I_00006_Media" => true,
                                 "6a35b0974f59819404dc86d48fe39fc3" => true,
                                 "I_00001_R" => true},
                        "all_quizzes" => "1",
                        "all_external_tools" => "0",
                        "all_groups" => "0",
                        "all_modules" => "0",
                        "all_rubrics" => "0",
                        "assessment_questions" => "1",
                        "all_wikis" => "0",
                        "all_files" => "0",
                        "all_assignments" => "1",
                        "topic_entries" => {"undefined" => true},
                        "external_tools" => {"I_00011_R" => true},
                        "shift_dates" => "0",
                        "all_topics" => "0",
                        "all_announcements" => "0",
                        "files" =>
                                {"I_00006_Media" => true,
                                 "7acb90d1653008e73753aa2cafb16298" => true,
                                 "6a35b0974f59819404dc86d48fe39fc3" => true,
                                 "I_00003_R_IMAGERESOURCE" => true,
                                 "I_00001_R" => true},
                        "modules" => {"I_00000" => true},
                        "all_assignment_groups" => "0"}}.with_indifferent_access

      @course.import_from_migration(@course_data, nil, @migration)
    end

    it "should selectively import files" do
      @course.attachments.count.should == 5
      @course.context_external_tools.count.should == 1
      @course.context_external_tools.first.migration_id.should == "I_00011_R"
      @course.context_modules.count.should == 1
      @course.context_modules.first.migration_id.should == 'I_00000'
      @course.wiki.wiki_pages.count.should == 0
      @course.discussion_topics.count.should == 1
      @course.discussion_topics.first.migration_id.should == 'I_00006_R'
    end
  end

end

describe "More Standard Common Cartridge importing" do
  before(:each) do
    @converter = get_standard_converter
    @copy_to = course_model
    @copy_to.name = "alt name"
    @copy_to.course_code = "alt name"

    @migration = Object.new
    @migration.stubs(:to_import).returns(nil)
    @migration.stubs(:context).returns(@copy_to)
    @migration.stubs(:import_object?).returns(true)
  end

  it "should properly handle top-level resource references" do
    orgs = <<-XML
<organizations>
  <organization structure="rooted-hierarchy" identifier="org_1">
    <item identifier="LearningModules">
      <item identifier="m1">
        <title>some module</title>
        <item identifier="ct2" identifierref="w1">
          <title>some page</title>
        </item>
      </item>
      <item identifier="ct5" identifierref="f3">
        <title>Super exciting!</title>
      </item>
      <item identifier="m2">
        <title>next module</title>
      </item>
      <item identifier="ct6" identifierref="f4">
        <title>test answers</title>
      </item>
      <item identifier="ct7" identifierref="f5">
        <title>test answers</title>
      </item>
    </item>
  </organization>
</organizations>
    XML

    #convert to json
    # pretend there were resources for the referenced items
    @converter.resources = {'w1' => {:type=>"webcontent"}, 'f3' => {:type=>"webcontent"}, 'f4' => {:type=>"webcontent"}, 'f5' => {:type=>"webcontent"}, }
    doc = Nokogiri::XML(orgs)
    hash = @converter.convert_organizations(doc)

    # make all the fake attachments for the module items to link to
    unfiled_folder = Folder.unfiled_folder(@copy_to)
    w1 = Attachment.create!(:filename => 'w1.html', :uploaded_data => StringIO.new('w1'), :folder => unfiled_folder, :context => @copy_to)
    w1.migration_id = "w1"; w1.save
    f3 = Attachment.create!(:filename => 'f3.html', :uploaded_data => StringIO.new('f3'), :folder => unfiled_folder, :context => @copy_to)
    f3.migration_id = "f3"; f3.save
    f4 = Attachment.create!(:filename => 'f4.html', :uploaded_data => StringIO.new('f4'), :folder => unfiled_folder, :context => @copy_to)
    f4.migration_id = "f4"; f4.save
    f5 = Attachment.create!(:filename => 'f5.html', :uploaded_data => StringIO.new('f5'), :folder => unfiled_folder, :context => @copy_to)
    f5.migration_id = "f5"; f5.save

    #import json into new course
    hash = hash.map { |h| h.with_indifferent_access }
    ContextModule.process_migration({'modules' =>hash}, @migration)
    @copy_to.save!

    @copy_to.context_modules.count.should == 3

    mod1 = @copy_to.context_modules.find_by_migration_id("m1")
    mod1.name.should == "some module"
    mod1.content_tags.count.should == 1
    mod1.position.should == 1
    tag = mod1.content_tags.last
    tag.content_id.should == w1.id
    tag.content_type.should == 'Attachment'
    tag.indent.should == 0

    mod2 = @copy_to.context_modules.find_by_migration_id("misc_module_top_level_items")
    mod2.name.should == "Misc Module"
    mod2.content_tags.count.should == 3
    mod2.position.should == 2
    tag = mod2.content_tags.first
    tag.content_id.should == f3.id
    tag.content_type.should == 'Attachment'
    tag.indent.should == 0
    tag = mod2.content_tags[1]
    tag.content_id.should == f4.id
    tag.content_type.should == 'Attachment'
    tag.indent.should == 0
    tag = mod2.content_tags[2]
    tag.content_id.should == f5.id
    tag.content_type.should == 'Attachment'
    tag.indent.should == 0

    mod3 = @copy_to.context_modules.find_by_migration_id("m2")
    mod3.name.should == "next module"
    mod3.content_tags.count.should == 0
    mod3.position.should == 3
  end

  it "should handle back-slashed paths" do
    resources = <<-XML
<resources>
  <resource href="a1\\a1.html" identifier="a1" type="webcontent" intendeduse="assignment">
    <file href="a1\\a1.html"/>
  </resource>
  <resource identifier="w1" type="webcontent">
    <file href="w1\\w1.html"/>
    <file href="w1\\w2.html"/>
  </resource>
  <resource identifier="q1" type="imsqti_xmlv1p2/imscc_xmlv1p2/assessment">
    <file href="q1\\q1.xml"/>
  </resource>
</resources>
    XML

    doc = Nokogiri::XML(resources)
    @converter.unzipped_file_path = 'testing/'
    @converter.get_all_resources(doc)
    @converter.resources['a1'][:href].should == 'a1/a1.html'
    @converter.resources['w1'][:files].first[:href].should == 'w1/w1.html'
    @converter.resources['w1'][:files][1][:href].should == 'w1/w2.html'
    @converter.resources['q1'][:files].first[:href].should == 'q1/q1.xml'
  end
end
