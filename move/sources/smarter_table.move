module addr::smarter_table {
    use aptos_std::smart_table::{Self, SmartTable};
    use aptos_std::table_with_length::{Self, TableWithLength};
    use aptos_std::aptos_hash::sip_hash_from_value;

    // This uses multiple smart tables to allow for many parallel buckets.
    struct SmarterTable<K, V> has key, store {
        num_tables: u64,
        tables: TableWithLength<u64, SmartTable<K, V>>
    }

    public fun new<K, V>(num_buckets: u64): SmarterTable<K, V> {
        let tables = table_with_length::new<u64, SmartTable<K, V>>();
        for (i in 0..num_buckets) {
            tables.add(i, smart_table::new::<K, V>());
        };
        SmarterTable<K, V> { num_tables: num_buckets, tables }
    }

    public fun add<K, V>(
        self: &mut SmarterTable<K, V>,
        key: K,
        value: V,
    ) {
        let hash = sip_hash_from_value(&key);
        let table = self.tables.borrow_mut(hash % self.num_tables);
        table.add(key, value);
    }

    /// Returns true iff `table` contains an entry for `key`.
    public fun contains<K: drop, V>(self: &SmarterTable<K, V>, key: K): bool {
        let hash = sip_hash_from_value(&key);
        let table = self.tables.borrow(hash % self.num_tables);
        table.contains(key)
    }

    public fun size<K: drop, V: drop>(self: &SmarterTable<K, V>): u64 {
        let size = 0;
        for (i in 0..self.num_tables) {
            let table = self.tables.borrow(i);
            size = size + table.length();
        };
        size
    }

    /// Destroy a table completely when V has `drop`.
    public fun destroy<K: drop, V: drop>(self: SmarterTable<K, V>) {
        let SmarterTable<K, V> {
            num_tables,
            tables
        } = self;

        for (i in 0..num_tables) {
            let t = tables.remove(i);
            t.destroy();
        };
        tables.destroy_empty();
    }
}
