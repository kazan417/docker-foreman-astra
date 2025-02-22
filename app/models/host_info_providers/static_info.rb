module HostInfoProviders
  class StaticInfo < HostInfo::Provider
    def host_info
      # Static parameters
      param = {}

      param["foreman_hostname"] = host.shortname unless host.shortname.nil?
      param["foreman_fqdn"] = host.fqdn unless host.fqdn.nil?
      param["hostgroup"] = host.hostgroup.to_label unless host.hostgroup.nil?
      param["comment"] = host.comment if host.comment.present?
      param["root_pw"] = host.root_pass unless (!host.operatingsystem.nil? && host.operatingsystem.password_hash == 'Base64')

      add_network_params param
      add_taxonomy_params param
      add_domain_params param
      add_login_params param
      add_certificate_params param

      # Parse ERB values contained in the parameters
      param = ParameterSafeRender.new(self).render(param)

      { 'parameters' => param }
    end

    private

    def add_login_params(param)
      owner = host.owner
      return unless owner

      param["owner_name"]  = owner.name
      param["owner_email"] = owner.is_a?(User) ? owner.mail : owner.users.map(&:mail)
      param["ssh_authorized_keys"] = host.ssh_authorized_keys
      param["foreman_users"] = owner.to_export
    end

    def add_domain_params(param)
      return if host.domain.blank?
      param["domainname"] = host.domain.name unless host.domain.nil? || host.domain.name.nil?
      param["foreman_domain_description"] = host.domain.fullname unless host.domain.nil? || host.domain.fullname.nil?
    end

    def add_taxonomy_params(param)
      ['location', 'organization'].each do |single_taxonomy|
        tax_field = host.send(single_taxonomy)
        next unless tax_field.present?

        param[single_taxonomy] = tax_field.name
        param["#{single_taxonomy}_title"] = tax_field.title
      end
    end

    def add_network_params(param)
      realm = host.realm
      param["realm"] = realm.name unless realm.nil?
      param['foreman_subnets'] = all_subnets.map(&:to_export).uniq
      param['foreman_interfaces'] = host.interfaces.map(&:to_export)
    end

    def add_certificate_params(param)
      param['server_ca'] = read_cert(Setting[:server_ca_file])
      param['ssl_ca'] = read_cert(Setting[:ssl_ca_file])
    end

    def read_cert(path)
      return nil unless path

      File.read(path)
    rescue StandardError => e
      Foreman::Logging.logger('app').warn("Failed to read CA file: #{e}")

      nil
    end

    def all_subnets
      host.interfaces.map { |i| [i.subnet, i.subnet6] }.flatten.compact
    end
  end
end
