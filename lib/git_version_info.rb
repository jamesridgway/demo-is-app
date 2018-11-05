class GitVersionInfo
  REVISION_FILENAME = "#{Rails.root}/REVISION".freeze

  def commit
    retrieve_commit_hash
  end

  def commit_short
    retrieve_commit_hash.to_s[0..7]
  end

  private

  def retrieve_commit_hash
    if File.exist?(REVISION_FILENAME)
      @version ||= File.open(REVISION_FILENAME).read.strip
    else
      'unknown'
    end
  end
end