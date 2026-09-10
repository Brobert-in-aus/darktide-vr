"""Exercise the decoded clustered-list initialization contract, not the game.

The normal list writers reserve contiguous ranges, publish masked heads, then
store packed links at unmasked indices. Model out-of-range stores as discarded.
Head exchange order and node-store completion order may differ.
"""
import random
import unittest


def build_events(allocations, seed):
    rng = random.Random(seed)
    jobs = []
    next_index = 0
    while next_index < allocations:
        count = min(rng.randint(1, 8), allocations - next_index)
        jobs.append([(next_index+i, rng.randrange(8), rng.randrange(500)) for i in range(count)])
        next_index += count
    events = []
    while jobs:
        job = rng.randrange(len(jobs))
        events.append(jobs[job].pop(0))
        if not jobs[job]:
            jobs.pop(job)
    return events


def run(capacity, events, initial, *, skip_store=None, initial_heads=None):
    mask = capacity-1
    bits = mask.bit_length()
    heads = [mask]*8 if initial_heads is None else list(initial_heads)
    counts = [0]*8
    stores = []
    for index, cluster, light in events:
        previous = heads[cluster]
        heads[cluster] = index & mask
        counts[cluster] += 1
        stores.append((index, (light << bits) | (previous & mask)))
    nodes = list(initial)
    written = set()
    # All stores complete before traversal; reverse order stresses that head
    # publication must not be mistaken for node-store completion.
    for index, value in reversed(stores):
        if index < capacity and index != skip_store:
            nodes[index] = value
            written.add(index)
    outputs = []
    for cluster, head in enumerate(heads):
        lights = []
        if not counts[cluster]:
            outputs.append(lights)
            continue
        cursor = head
        # The decoded compaction consumer follows at most 32 nodes. Overflow
        # can form cycles or hit the reserved sentinel; equivalence is not a
        # claim that the stock overflow result is complete or desirable.
        for _ in range(32):
            if cursor == mask:
                break
            value = nodes[cursor]
            lights.append(value >> bits)
            cursor = value & mask
        outputs.append(lights)
    return heads, counts, outputs, written


class ClusterInitializationTests(unittest.TestCase):
    def test_contiguous_complete_writes_make_prior_contents_unreachable(self):
        for capacity in (8, 16, 64, 256):
            for count in (0, 1, capacity-1, capacity, capacity+1, 2*capacity+9):
                for seed in range(32):
                    rng = random.Random(seed+1234)
                    stale = [rng.getrandbits(32) for _ in range(capacity)]
                    events = build_events(count, seed)
                    cleared = run(capacity, events, [0xffffffff]*capacity)
                    retained = run(capacity, events, stale)
                    self.assertEqual(cleared, retained)
                    self.assertEqual(retained[3], set(range(min(count, capacity))))

    def test_missing_store_breaks_the_contract(self):
        events = [(0, 0, 7)]
        cleared = run(8, events, [0xffffffff]*8, skip_store=0)
        retained = run(8, events, [0]*8, skip_store=0)
        self.assertNotEqual(cleared[2], retained[2])

    def test_counter_not_reset_breaks_the_contract_on_wrap(self):
        events = [(8, 0, 7)]
        self.assertNotEqual(run(8, events, [0xffffffff]*8)[2],
                            run(8, events, [0]*8)[2])

    def test_head_not_reset_can_reach_untouched_storage(self):
        heads = [3]+[7]*7
        events = [(0, 0, 7)]
        self.assertNotEqual(run(8, events, [0xffffffff]*8, initial_heads=heads)[2],
                            run(8, events, [0]*8, initial_heads=heads)[2])


if __name__ == '__main__':
    unittest.main()
