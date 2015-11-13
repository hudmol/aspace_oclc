require 'net/http'
require 'oclc/auth'
require 'asutils'
require 'rufus/lru'

class OCLCMetadataException < StandardError; end


class OCLCBibGetter < Struct.new(:base_url, :key, :secret, :principal_id)

  def self.cache
    @cache ||= Rufus::Lru::Hash.new(10)
  end

  def self.principal_idns
    'urn:oclc:wms:da'
  end


  def cache
    self.class.cache
  end


  def write_records(ids)

    tempfiles = []

    get_records(ids).each do |record|

      tempfile = ASUtils.tempfile('oclc_import')
      tempfile.write(record[:xml])

      tempfile.flush
      tempfile.rewind

      tempfiles << tempfile
    end

    tempfiles
  end


  def get_records(oclcns)
    records = []

    oclcns.each do |oclcn|
      begin
        xml = self.get(oclcn)
        if xml =~ /Record does not exist/
          records << {:oclcn => oclcn, :error => xml}
        else
          records << {:oclcn => oclcn, :xml => xml}
        end
      rescue OCLCMetadataException => e
        records << {:oclcn => oclcn, :error => e.message}
      rescue Exception => e
        records << {:oclc => oclcn, :error => e.message}
      end
    end

    records
  end


  def get(oclcn)
    unless cache.has_key?(oclcn)
      @wskey ||= OCLC::Auth::WSKey.new(key, secret)

      url = "#{base_url}/#{oclcn.to_s}?classificationScheme=LibraryOfCongress"
      uri = URI.parse(url)

      request = Net::HTTP::Get.new(uri.request_uri)
      request['Authorization'] = @wskey.hmac_signature('GET', url, :principal_id => principal_id, :principal_idns => self.class.principal_idns)
      request['Accept'] = "application/atom+xml;content=\"application/vnd.oclc.marc21+xml\""

      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.ssl_version = :TLSv1

      response = http.start do |http| 
        http.request(request)
      end

      if response.code != '200'
        raise OCLCMetadataException.new("Error returned by OCLC Metadata API: #{response.body}")
      end


      cache[oclcn] = response.body.force_encoding('UTF-8')
    end

    cache[oclcn]
  end

end

