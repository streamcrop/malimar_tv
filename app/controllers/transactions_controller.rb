class TransactionsController < ApplicationController
	def accept
		@transaction = Transaction.find(params[:id])
		if @transaction.roku_id.present?
			@device = Roku.find(@transaction.roku_id)
			if @device.expiry.blank?
				details = YAML.load(@transaction.product_details)
				@device.expiry = Date.today+details[:duration].months
				@device.save
			else
				details = YAML.load(@transaction.product_details)
				@device.expiry += details[:duration].months
				@device.save
			end
		else
			@user = User.find(@transaction.user_id)
			if @user.expiry.blank?
				details = YAML.load(@transaction.product_details)
				@user.expiry = Date.today+details[:duration].months
				@user.save
			else
				details = YAML.load(@transaction.product_details)
				@user.expiry += details[:duration].months
				@user.save
			end
		end
		@transaction.customer_paid = DateTime.now
		@transaction.status = 'Paid'
		if @transaction.save
			TransactionalMailer.order_paid(@transaction, @user).deliver
			AdminActivity.create(admin_id: current_admin.id,
								data: YAML.dump({
									type: 'Accepted Payment',
									message: "#{current_admin.name} accepted a payment.",
									tx_details: {
										user_id: @transaction.user_id,
										name: details[:name],
										duration: details[:duration],
										price: details[:price]
									}
								}))
			flash[:success] = "Order \##{@transaction.id} has been accepted."
			OrderNotification.create(transaction_id: @transaction.id,message: "Order \##{@transaction.id} has been accepted.", link: true)
		end
	end

	def cancel
		@transaction = Transaction.find(params[:id])
		@user = User.find(@transaction.user_id)
		@transaction.customer_refunded = DateTime.now
		@transaction.status = 'Cancelled'
		details = YAML.load(@transaction.product_details)
		details[:name] = 'CANCELLED: '+ details[:name]
		@transaction.product_details = YAML.dump(details)
		if @transaction.save
			AdminActivity.create(admin_id: current_admin.id,
								data: YAML.dump({
									type: 'Cancelled Payment',
									message: "#{current_admin.name} cancelled a payment.",
									tx_details: {
										user_id: @transaction.user_id,
										name: details[:name],
										duration: details[:duration],
										price: details[:price]
									}
								}))
			flash[:success] = "Order \##{@transaction.id} has been cancelled."
			OrderNotification.create(transaction_id: @transaction.id,message: "Order \##{@transaction.id} has been cancelled.", link: true)
		end
	end

	def refund
		@transaction = Transaction.find(params[:id])

		if @transaction.paypal_id.nil?
			@user = User.find(@transaction.user_id)
			@transaction.customer_refunded = DateTime.now
			@transaction.status = 'Refunded'
			details = YAML.load(@transaction.product_details)
			details[:name] = 'REFUNDED: '+ details[:name]
			@transaction.product_details = YAML.dump(details)
			if @transaction.save
				@message = "Transaction \##{@transaction.id} successfully refunded!"
				@success = true
				AdminActivity.create(admin_id: current_admin.id,
									data: YAML.dump({
										type: 'Refunded Payment',
										message: "#{current_admin.name} refunded a payment.",
										tx_details: {
											user_id: @transaction.user_id,
											name: details[:name],
											duration: details[:duration],
											price: details[:price]
										}
									}))
				flash[:success] = "Order \##{@transaction.id} has been refunded."
				OrderNotification.create(transaction_id: @transaction.id,message: "Order \##{@transaction.id} has been refunded.", link: true)
			end
		else
			@paypal = YAML.load(Setting.where(name: 'Paypal Credentials').first.data)
			gateway = ActiveMerchant::Billing::PaypalGateway.new(
				login:    	@paypal[:login],
				password: 	@paypal[:password],
				signature: 	@paypal[:signature]
			)

			response = gateway.refund nil, @transaction.paypal_id
			if response.success?
				@transaction.status = 'Refunded'
				details = YAML.load(@transaction.product_details)
				details[:name] = 'REFUNDED: '+ details[:name]
				@transaction.product_details = YAML.dump(details)
				@transaction.save
				@message = "Transaction \##{@transaction.id} successfully refunded!"
				@success = true
				AdminActivity.create(admin_id: current_admin.id,
									data: YAML.dump({
										type: 'Refunded Payment',
										message: "#{current_admin.name} refunded a payment.",
										tx_details: {
											user_id: @transaction.user_id,
											name: details[:name],
											duration: details[:duration],
											price: details[:price]
										}
									}))
				flash[:success] = "Order \##{@transaction.id} has been refunded."
				OrderNotification.create(transaction_id: @transaction.id,message: "Order \##{@transaction.id} has been refunded.", link: true)
			else
				@success = false
				@message = 'There was an error refunding this transaction.'
			end
		end
	end

	# TODO
	# User view all


	def view_invoice
		transaction = Transaction.find(params[:id])

		if admin_signed_in? || (user_signed_in? && current_user.id == transaction.user_id)
			send_data transaction.invoice, filename: "Invoice \##{transaction.id} - #{transaction.created_at.strftime('%d/%M/%Y')}", :type => "application/pdf", :disposition => "inline"
		else
			redirect_to '/'
		end
	end

	def index
		search_hash = Hash.new
		if params[:search].present? || params[:payment_type].present? || params[:status].present?
			@transactions = Array.new
			if params[:search].present?
				begin
					order_number = Integer(params[:search])
					@transactions = Transaction.where(id: order_number)
				rescue => e
					users = User.all
					if params[:payment_type].present?
						search_hash[:payment_type] = params[:payment_type]
					end
					if params[:status].present?
						search_hash[:status] = params[:status]
					end

					users.each do |user|
						if user.matches?(params[:search])
							search_hash[:user_id] = user.id
							txs = Transaction.where(search_hash)
							txs.each do |tx|
								@transactions.push(tx)
							end
						end
					end
				end
			else
				if params[:payment_type].present?
					search_hash[:payment_type] = params[:payment_type]
				end
				if params[:status].present?
					search_hash[:status] = params[:status]
				end

				txs = Transaction.where(search_hash)
				txs.each do |tx|
					@transactions.push(tx)
				end
			end
		else
			@transactions = Transaction.all
		end
	end

	def show
		@transaction = Transaction.find(params[:id])
		@data = YAML.load(@transaction.product_details)
		if @transaction.sales_rep_id.present?
			@rep = SalesRepresentative.where(id: @transaction.sales_rep_id).first
		end
		@user = User.where(id: @transaction.user_id).first
		if @transaction.roku_id.present?
			@roku_attached = true
			@roku = Roku.where(id: @transaction.roku_id).first
		else
			@roku_attached = false
			@roku = nil
		end
	end

	def view_all
		transactions = Transaction.where(user_id: params[:id]).order(created_at: :desc)
		Payday::Config.default.invoice_logo = "#{Rails.root}/app/assets/images/logo.png"
		Payday::Config.default.company_name = "Malimar TV"
		Payday::Config.default.company_details = "10 This Way\nManhattan, NY 10001\n800-111-2222\nbilling@malimar-tv.com"

		invoice = Payday::Invoice.new(invoice_number: transaction.id, notes: 'This is a full record of your transactions with MalimarTV')

		transactions.each do |transaction|
			details = YAML.load(transaction.product_details)
			invoice.line_items << Payday::LineItem.new(price: details[:price]*100, description: "#{details[:plan]}: #{details[:duration]} month(s) | #{details.status}")
		end
	end
end
