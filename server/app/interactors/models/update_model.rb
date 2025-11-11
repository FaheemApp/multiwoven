# frozen_string_literal: true

module Models
  class UpdateModel
    include Interactor

    def call
      model = context.model
      query_changed = model.query != context.model_params[:query]

      unless model.update(context.model_params)
        context.fail!(model: context.model)
        return
      end

      Models::SchemaCacheService.new(model).call(force: query_changed)
    end
  end
end
