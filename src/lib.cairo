
#[starknet::contract]
mod Oracle {
    use starknet::ContractAddress;
    use starknet::get_caller_address;
    use starknet::get_block_timestamp;

    #[derive(Copy, Serde, starknet::Store, Drop)]
    struct Price {
        value: u256,
        decimal: u8,
        timestamp: u64,
    }

    #[storage]
    struct Storage {
        owner: LegacyMap::<ContractAddress, bool>,
        feeders: LegacyMap<ContractAddress, bool>,
        paris: LegacyMap::<u8, bool>,
        price_oracles: LegacyMap::<u8, Price>,
        update_interval: u64,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        SetOwner: SetOwner,
        SetFeeder: SetFeeder,
        SetUpdateInterval: SetUpdateInterval,
        RegisterTokenPrice: RegisterTokenPrice,
        UpdateTokenPrice: UpdateTokenPrice,
        UpdateTokenPriceBatch: UpdateTokenPriceBatch,
    }

    #[derive(Drop, starknet::Event)]
    struct SetOwner {
        #[key]
        old: ContractAddress,
        new: ContractAddress
    }

    #[derive(Drop, starknet::Event)]
    struct SetFeeder {
        #[key]
        admin: ContractAddress,
        feeder: ContractAddress,
        valid: bool
    }

    #[derive(Drop, starknet::Event)]
    struct SetUpdateInterval {
        #[key]
        admin: ContractAddress,
        interval: u64
    }

    #[derive(Drop, starknet::Event)]
    struct RegisterTokenPrice {
        #[key]
        admin: ContractAddress,
        #[key]
        tid: u8,
        price: u256,
        timestamp: u64
    }

    #[derive(Drop, starknet::Event)]
    struct UpdateTokenPrice {
        #[key]
        feeder: ContractAddress,
        #[key]
        tid: u8,
        price: u256,
        timestamp: u64
    }

    #[derive(Drop, starknet::Event)]
    struct UpdateTokenPriceBatch {
        #[key]
        feeder: ContractAddress,
        #[key]
        tids: Span<u8>,
        prices: Span<u256>,
        timestamps: Span<u64>
    }

    #[constructor]
    fn constructor(
        ref self: ContractState, 
        timeout: u64
    ) {
        let o = get_caller_address();
        self.owner.write(o, true);
        self.update_interval.write(timeout);
    }

    #[external(v0)]
    fn set_owner(
        ref self: ContractState, 
        owner: ContractAddress
    ) {
        let sender = get_caller_address();
        let is_owner = self.owner.read(sender);
        assert(is_owner, 'not owner');
        assert(!owner.is_zero(), 'owner address error');

        self.owner.write(sender, false);
        self.owner.write(owner, true);
        self.emit(SetOwner { old: sender, new: owner });
    }

    #[external(v0)]
    fn set_feeder(
        ref self: ContractState, 
        feeder: ContractAddress,
        valid: bool
    ) {
        let sender = get_caller_address();
        let is_owner = self.owner.read(sender);
        assert(is_owner, 'not owner');
        assert(!feeder.is_zero(), 'feeder address error');

        self.feeders.write(feeder, valid);
        self.emit(SetFeeder { admin: sender, feeder: feeder, valid: valid});
    }

    #[external(v0)]
    fn set_update_interval(
        ref self: ContractState, 
        update_interval: u64
    ) {
        let sender = get_caller_address();
        let is_owner = self.owner.read(sender);
        assert(is_owner, 'not owner');

        self.update_interval.write(update_interval);
        self.emit(SetUpdateInterval { admin: sender, interval: update_interval });
    }

    #[external(v0)]
    fn register_token_price(
        ref self: ContractState,
        tid: u8,
        token_price: u256,
        price_decimal: u8
    ) {
        let sender = get_caller_address();
        let is_owner = self.owner.read(sender);
        assert(is_owner, 'not owner');

        let tid_exsited = self.paris.read(tid);
        assert(!tid_exsited, 'token existed');

        assert(token_price > 0, 'token price error');

        let ts = get_block_timestamp();
		let p = Price{
            value: token_price, 
            decimal: price_decimal, 
            timestamp: ts
            };
        self.price_oracles.write(tid, p);
        self.paris.write(tid, true);
        self.emit(RegisterTokenPrice { admin: sender, tid: tid, price: token_price, timestamp: ts });
    }

    #[external(v0)]
    fn update_token_price(
        ref self: ContractState,
        tid: u8,
        token_price: u256,
        price_decimal: u8,
        timestamp: u64 
    ) {
        let sender = get_caller_address();
        let is_feeder = self.feeders.read(sender);
        assert(is_feeder, 'not feeder');

        let tid_exsited = self.paris.read(tid);
        assert(tid_exsited, 'token not existed');
        assert(token_price > 0, 'token price error');
        let ts = get_block_timestamp();
        assert(ts - timestamp <= self.update_interval.read(), 'timestamp error');

        let p = self.price_oracles.read(tid);
		let price = Price{
            value: token_price, 
            decimal: p.decimal, 
            timestamp: timestamp
            };
        self.price_oracles.write(tid, p);
        self.emit(UpdateTokenPrice { feeder: sender, tid: tid, price: token_price, timestamp: timestamp });
    }

    #[external(v0)]
    fn update_token_price_batch(
        ref self: ContractState,
        tids: Span<u8>,
        token_prices: Span<u256>,
        timestamps: Span<u64> 
    ) {
        let sender = get_caller_address();
        let is_feeder = self.feeders.read(sender);
        assert(is_feeder, 'not feeder');

        let len = tids.len();
        assert(len > 0 && len == token_prices.len() && len == timestamps.len(), 'bad ids & prices & ts len');

        let ts = get_block_timestamp();
        let mut i: usize = 0;
        loop {
            if (i >= len) {
                break ();
            }

            let tid = *tids.at(i);
            let price = *token_prices.at(i);
            let timestamp = *timestamps.at(i);

            let tid_exsited = self.paris.read(tid);
            assert(tid_exsited, 'token not existed');
            assert(price > 0, 'token price error');
        
            assert(ts - timestamp <= self.update_interval.read(), 'timestamp error');

            let p = self.price_oracles.read(tid);
		    let price = Price{
                value: price, 
                decimal: p.decimal, 
                timestamp: timestamp
            };
            self.price_oracles.write(tid, p);

            i += 1;
        };
        self.emit(UpdateTokenPriceBatch { feeder: sender, tids: tids, prices: token_prices, timestamps: timestamps });
    }

	#[external(v0)]
    fn get_token_price(self: @ContractState, tid: u8) -> (bool, u256, u8) {
        let p = self.price_oracles.read(tid);
        (true, p.value, p.decimal)
    }
	
}