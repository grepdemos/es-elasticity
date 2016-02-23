module Elasticity
  class MultiSearch

    def initialize
      @searches = {}
      @mappers  = {}
      yield self if block_given?
    end

    def add(name, search, documents: nil, active_records: nil)
      if !documents.nil? && !active_records.nil?
        raise ArgumentError, "you can only pass either :documents or :active_records as an option"
      elsif documents.nil? && active_records.nil?
        raise ArgumentError, "you need to provide either :documents or :active_records as an option"
      end

      @searches[name] = {
        search_definition: search.search_definition,
        documents: documents,
        active_records: active_records
      }

      name
    end

    def [](name)
      results_collection[name]
    end

    private

    def results_collection
      @results_collection ||= fetch
    end

    def fetch
      bodies = @searches.values.map do |hsh|
        hsh[:search_definition].to_msearch_args
      end

      response = ActiveSupport::Notifications.instrument("multi_search.elasticity", args: { body: bodies }) do
        Elasticity.config.client.msearch(body: bodies.map(&:dup))
      end
      results = {}

      @searches.keys.each_with_index do |name, idx|
        resp = response["responses"][idx]
        search = @searches[name]

        results[name] = case
        when search[:documents]
          Search::Results.new(resp, bodies[idx], search[:documents].method(:map_hit))
        when search[:active_records]
          Search::ActiveRecordProxy.map_response(search[:active_records], bodies[idx], resp)
        end
      end

      results
    end
  end
end
