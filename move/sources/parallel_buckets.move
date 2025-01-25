module addr::parallel_buckets {
    use std::option;
    use aptos_std::table_with_length::{Self, TableWithLength};

    // This uses multiple tables to allow for many parallel buckets.
    struct ParallelBuckets<V: drop + store> has key, store {
        num_buckets: u64,
        buckets: TableWithLength<u64, vector<V>>
    }

    public fun new<V: drop + store>(num_buckets: u64): ParallelBuckets<V> {
        let buckets = table_with_length::new<u64, vector<V>>();
        for (i in 0..num_buckets) {
            buckets.add(i, vector[]);
        };
        ParallelBuckets { num_buckets, buckets }
    }

    public fun add<V: drop + store>(
        self: &mut ParallelBuckets<V>,
        value: V,
        random: u64,
    ) {
        let bucket_index = random % self.num_buckets;
        let bucket = self.buckets.borrow_mut(bucket_index);
        bucket.push_back(value);
    }

    /// Adds the values to all of the buckets, starting with a random bucket
    public fun add_many_evenly<V: drop + store>(
        self: &mut ParallelBuckets<V>,
        values: vector<V>,
        random: u64,
    ) {
        let bucket_index = random % self.num_buckets;
        let me = self;
        values.for_each(|value| {
            let bucket = me.buckets.borrow_mut(bucket_index);
            bucket.push_back(value);
            bucket_index = (bucket_index + 1) % me.num_buckets;
        });
    }


    public fun pop<V: drop + store>(
        self: &mut ParallelBuckets<V>,
        random: u64,
    ): option::Option<V> {
        let bucket_index = random % self.num_buckets;
        let buckets_left = self.num_buckets;

        let bucket = self.buckets.borrow_mut(bucket_index);
        while (bucket.is_empty()) {
            bucket_index = (bucket_index + 1) % self.num_buckets;
            bucket = self.buckets.borrow_mut(bucket_index);
            buckets_left = buckets_left - 1;
            if (buckets_left == 0) {
                break;
            }
        };
        if (bucket.is_empty()) {
            option::none<V>()
        } else {
            option::some(bucket.pop_back())
        }
    }

    public fun destroy<V: drop + store>(
        self: ParallelBuckets<V>,
    ) {
        let ParallelBuckets<V> {
            num_buckets,
            buckets
        } = self;

        // Drop all the stuff in side
        for (i in 0..num_buckets) {
            let _ = buckets.remove(i);
        };

        buckets.destroy_empty();
    }
}
