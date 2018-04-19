shared_examples_for "ansible refresher_v2" do |ansible_provider, manager_class, ems_type, cassette_path|
  # To change credentials in cassettes:
  # replace with defaults - before committing
  # ruby -pi -e 'gsub /yourdomain.com/, "example.com"; gsub /admin:smartvm/, "testuser:secret"' spec/vcr_cassettes/manageiq/providers/ansible_tower/automation_manager/refresher_v2.yml
  # replace with your working credentials
  # ruby -pi -e 'gsub /example.com/, "yourdomain.com"; gsub /testuser:secret/, "admin:smartvm"' spec/vcr_cassettes/manageiq/providers/ansible_tower/automation_manager/refresher_v2.yml
  let(:tower_url) { ENV['TOWER_URL'] || "https://dev-ansible-tower3.example.com/api/v1/" }
  let(:auth_userid) { ENV['TOWER_USER'] || 'testuser' }
  let(:auth_password) { ENV['TOWER_PASSWORD'] || 'secret' }

  let(:auth)                    { FactoryGirl.create(:authentication, :userid => auth_userid, :password => auth_password) }
  let(:automation_manager)      { provider.automation_manager }
  let(:expected_counterpart_vm) { FactoryGirl.create(:vm, :uid_ems => "4233080d-7467-de61-76c9-c8307b6e4830") }
  let(:provider) do
    _guid, _server, zone = EvmSpecHelper.create_guid_miq_server_zone
    FactoryGirl.create(ansible_provider,
                       :zone       => zone,
                       :url        => tower_url,
                       :verify_ssl => false,).tap { |provider| provider.authentications << auth }
  end
  let(:manager_class) { manager_class }

  it ".ems_type" do
    expect(described_class.ems_type).to eq(ems_type)
  end

  it "will perform a full refresh" do
    expected_counterpart_vm

    Spec::Support::VcrHelper.with_cassette_library_dir(ManageIQ::Providers::AnsibleTower::Engine.root.join("spec/vcr_cassettes")) do
      2.times do
        VCR.use_cassette("#{cassette_path}_v2") do
          EmsRefresh.refresh(automation_manager)
          expect(automation_manager.reload.last_refresh_error).to be_nil
        end

        assert_counts
        assert_configured_system
        assert_configuration_script_with_nil_survey_spec
        assert_configuration_script_with_survey_spec
        assert_inventory_root_group
        assert_configuration_script_sources
        assert_playbooks
        assert_credentials
      end
    end
  end

  def assert_counts
    expect(Provider.count).to                                    eq(1)
    expect(automation_manager).to                             have_attributes(:api_version => "3.2.2")
    expect(automation_manager.configured_systems.count).to    eq(2)
    expect(automation_manager.configuration_scripts.count).to eq(3)
    expect(automation_manager.inventory_groups.count).to      eq(2)
    expect(automation_manager.configuration_script_sources.count).to eq(7)
    expect(automation_manager.configuration_script_payloads.count).to eq(139)
    expect(automation_manager.credentials.count).to eq(17)
  end

  def assert_credentials
    expect(expected_configuration_script.authentications.count).to eq(3)
    machine_credential = expected_configuration_script.authentications.find_by(
      :type => manager_class::MachineCredential
    )
    expect(machine_credential).to have_attributes(
      :name   => "hello_machine_cred",
      :userid => "admin",
    )

    cloud_credential = expected_configuration_script.authentications.find_by(
      :type => manager_class::AmazonCredential
    )
    expect(cloud_credential).to have_attributes(
      :name   => "hello_aws_cred",
      :userid => "ABC",
    )

    scm_credential = expected_configuration_script_source.authentication
    expect(scm_credential).to have_attributes(
      :name   => "hello_scm_cred",
      :userid => "admin"
    )
    expect(scm_credential.options.keys).to match_array(scm_credential.class::EXTRA_ATTRIBUTES.keys)
  end

  def assert_playbooks
    expect(expected_configuration_script_source.configuration_script_payloads.first).to be_an_instance_of(manager_class::Playbook)
    expect(expected_configuration_script_source.configuration_script_payloads.count).to eq(61)
    expect(expected_configuration_script_source.configuration_script_payloads.map(&:name)).to include('jboss-standalone/site.yml')
  end

  def assert_configuration_script_sources
    expect(automation_manager.configuration_script_sources.count).to eq(7)
    expect(expected_configuration_script_source).to be_an_instance_of(manager_class::ConfigurationScriptSource)
    expect(expected_configuration_script_source).to have_attributes(
      :name        => 'hello_repo',
      :description => '',
    )
  end

  def assert_configured_system
    expect(expected_configured_system).to have_attributes(
      :type                 => manager_class::ConfiguredSystem.name,
      :hostname             => "hello_vm",
      :manager_ref          => "24",
      :virtual_instance_ref => "4233080d-7467-de61-76c9-c8307b6e4830",
    )
    expect(expected_configured_system.counterpart).to          eq(expected_counterpart_vm)
    expect(expected_configured_system.inventory_root_group).to eq(expected_inventory_root_group)
  end

  def assert_configuration_script_with_nil_survey_spec
    expect(expected_configuration_script).to have_attributes(
      :name        => "hello_template",
      :description => "test job",
      :manager_ref => "72",
      :survey_spec => {},
      :variables   => {}
    )
    expect(expected_configuration_script.inventory_root_group).to have_attributes(:ems_ref => "24")
    expect(expected_configuration_script.parent.name).to eq('hello_world.yml')
    expect(expected_configuration_script.parent.configuration_script_source.manager_ref).to eq('70')
  end

  def assert_configuration_script_with_survey_spec
    system = automation_manager.configuration_scripts.where(:name => "hello_template_with_survey").first
    expect(system).to have_attributes(
      :name        => "hello_template_with_survey",
      :description => "test job with survey spec",
      :manager_ref => "73",
      :variables   => {}
    )
    survey = system.survey_spec
    expect(survey).to be_a Hash
    expect(survey['spec'].first['question_name']).to eq('example question')
  end

  def assert_inventory_root_group
    expect(expected_inventory_root_group).to have_attributes(
      :name    => "hello_inventory",
      :ems_ref => "24",
      :type    => "ManageIQ::Providers::AutomationManager::InventoryRootGroup",
    )
  end

  private

  def expected_configured_system
    @expected_configured_system ||= automation_manager.configured_systems.where(:hostname => "hello_vm").first
  end

  def expected_configuration_script
    @expected_configuration_script ||= automation_manager.configuration_scripts.where(:name => "hello_template").first
  end

  def expected_inventory_root_group
    @expected_inventory_root_group ||= automation_manager.inventory_groups.where(:name => "hello_inventory").first
  end

  def expected_configuration_script_source
    @expected_configuration_script_source ||= automation_manager.configuration_script_sources.find_by(:name => 'hello_repo')
  end
end
