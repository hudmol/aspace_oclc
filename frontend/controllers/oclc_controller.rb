require 'securerandom'


class OclcController <  ApplicationController
  set_access_control "update_accession_record" => [:import, :preview, :index]

  def index
    missing = []

    %w(metadata_key metadata_secret principal_id).each do |setting|
      unless AppConfig.has_key?(:"oclc_#{setting}")
        missing << I18n.t("plugins.oclc.#{setting}")
      end
    end

    unless session[:repo_id]
      flash[:warning] = I18n.t('plugins.oclc.messages.no_repo')
    end

    unless missing.empty?
      flash[:warning] = I18n.t('plugins.oclc.messages.missing_from_config', :params => missing.join(", "))
    end

    render "search/index"
  end


  def preview(oclcns)

    begin 
      results = {:records => record_getter.get_records(oclcns)}

      render :json => ASUtils.to_json(results)

    rescue OCLCMetadataException => e
      render :json => {:error => e.message}
    end
  end


  def import
    oclcns = params[:ids].split(/\D+/).uniq.select {|id| id =~ /^\d+$/}

    OCLCLog.log("Import OCLCNs: #{oclcns.join(', ')}")

    if oclcns.count > 10
      render :json => {:error => I18n.t("plugins.oclc.messages.fewer_than_ten") + oclcns.join(', ')}
      return
    end
    
    if params[:preview]
      preview(oclcns)
      return
    end

    begin
      files = record_getter.write_records(oclcns)
      job = Job.new("marcxml_accession", 
                    Hash[files.map {|file| ["oclc_import_#{SecureRandom.uuid}", file] }])
        
      OCLCLog.log("Job Object:")
      OCLCLog.log job.inspect

      response = job.upload

      OCLCLog.log response.inspect
      render :json => {'job_uri' => url_for(:controller => :jobs, :action => :show, :id => response['id'])}
    rescue
      OCLCLog.log "Rescue Job Redirect Error"
      OCLCLog.log $!.to_s
      render :json => {'error' => $!.to_s}
    end
  end


  def unauthorised_access
    respond_to do |format|
      format.html {
        super
      }
      format.js {
        render :status => 403, :text => "Unauthorized Access"
      }
    end
  end

  private

  def record_getter
    @opts ||= [:oclc_metadata_key, :oclc_metadata_secret, :oclc_principal_id].map {|setting| AppConfig[setting]}

    @getter ||= OCLCBibGetter.new(OCLCBaseUrl.metadata_api, *@opts)
  end
end
