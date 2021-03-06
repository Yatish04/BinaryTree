#!python
#cython: boundscheck=False
#cython: wraparound=False
#cython: cdivision=True

__all__ = ['KDTree']

DOC_DICT = {'BinaryTree':'KDTree'}

VALID_METRICS = ['EuclideanDistance', 'ManhattanDistance', 'MinkowskiDistance']

include "binary_tree.pxi"

KDTree = BinaryTree

cdef void allocate_data(BinaryTree bt, ITYPE_t n_nodes, ITYPE_t n_features):
    bt.node_bounds = np.zeros((2, n_nodes, n_features), dtype=DTYPE)

cdef void init_node(BinaryTree bt, ITYPE_t i_node,
                    ITYPE_t idx_start, ITYPE_t idx_end):
    cdef ITYPE_t n_features = bt.data.shape[1]
    cdef ITYPE_t i, j, idx_i

    # determine Node bounds
    for j in range(n_features):
        bt.node_bounds[0, i_node, j] = INF
        bt.node_bounds[1, i_node, j] = -INF

    for i in range(idx_start, idx_end):
        idx_i = bt.idx_array[i]
        for j in range(n_features):
            bt.node_bounds[0, i_node, j] =\
                fmin(bt.node_bounds[0, i_node, j],
                     bt.data[idx_i, j])
            bt.node_bounds[1, i_node, j] =\
                fmax(bt.node_bounds[1, i_node, j],
                     bt.data[idx_i, j])

    bt.node_data[i_node].idx_start = idx_start
    bt.node_data[i_node].idx_end = idx_end

cdef DTYPE_t min_rdist(BinaryTree bt, ITYPE_t i_node, DTYPE_t* pt):
    cdef ITYPE_t n_features = bt.data.shape[1]
    cdef DTYPE_t d, d_lo, d_hi, rdist=0.0
    cdef ITYPE_t j

    # here we'll use the fact that x + abs(x) = 2 * max(x, 0)
    for j in range(n_features):
        d_lo = bt.node_bounds[0, i_node, j] - pt[j]
        d_hi = pt[j] - bt.node_bounds[1, i_node, j]
        d = (d_lo + fabs(d_lo)) + (d_hi + fabs(d_hi))
        rdist += pow(0.5 * d, bt.dm.p)

    return rdist

cdef DTYPE_t min_dist(BinaryTree bt, ITYPE_t i_node, DTYPE_t* pt):
    return pow(min_rdist(bt, i_node, pt), 1. / bt.dm.p)

cdef DTYPE_t max_rdist(BinaryTree bt, ITYPE_t i_node, DTYPE_t* pt):
    cdef ITYPE_t n_features = bt.data.shape[1]

    cdef DTYPE_t d, d_lo, d_hi, rdist=0.0
    cdef ITYPE_t j

    for j in range(n_features):
        d_lo = fabs(pt[j] - bt.node_bounds[0, i_node, j])
        d_hi = fabs(pt[j] - bt.node_bounds[1, i_node, j])
        rdist += pow(fmax(d_lo, d_hi), bt.dm.p)

    return rdist

cdef DTYPE_t max_dist(BinaryTree bt, ITYPE_t i_node, DTYPE_t* pt):
    return pow(max_rdist(bt, i_node, pt), 1. / bt.dm.p)

cdef inline void min_max_dist(BinaryTree bt, ITYPE_t i_node, DTYPE_t* pt,
                              DTYPE_t* min_dist, DTYPE_t* max_dist):
    cdef ITYPE_t n_features = bt.data.shape[1]

    cdef DTYPE_t d, d_lo, d_hi
    cdef ITYPE_t j

    min_dist[0] = 0.0
    max_dist[0] = 0.0

    # as above, use the fact that x + abs(x) = 2 * max(x, 0)
    for j in range(n_features):
        d_lo = bt.node_bounds[0, i_node, j] - pt[j]
        d_hi = pt[j] - bt.node_bounds[1, i_node, j]
        d = (d_lo + fabs(d_lo)) + (d_hi + fabs(d_hi))
        min_dist[0] += pow(0.5 * d, bt.dm.p)
        max_dist[0] += pow(fmax(fabs(d_lo), fabs(d_hi)), bt.dm.p)

    min_dist[0] = pow(min_dist[0], 1. / bt.dm.p)
    max_dist[0] = pow(max_dist[0], 1. / bt.dm.p)


cdef inline DTYPE_t min_rdist_dual(BinaryTree bt, ITYPE_t i_node1,
                                   BinaryTree bt2, ITYPE_t i_node2):
    cdef ITYPE_t n_features = bt.data.shape[1]

    cdef DTYPE_t d, d1, d2, rdist=0.0
    cdef DTYPE_t zero = 0.0
    cdef ITYPE_t j

    # here we'll use the fact that x + abs(x) = 2 * max(x, 0)
    for j in range(n_features):
        d1 = (bt.node_bounds[0, i_node1, j]
              - bt2.node_bounds[1, i_node2, j])
        d2 = (bt2.node_bounds[0, i_node2, j]
              - bt.node_bounds[1, i_node1, j])
        d = (d1 + fabs(d1)) + (d2 + fabs(d2))

        rdist += pow(0.5 * d, bt.dm.p)

    return rdist

cdef inline DTYPE_t min_dist_dual(BinaryTree bt1, ITYPE_t i_node1,
                                  BinaryTree bt2, ITYPE_t i_node2):
    return bt1.dm.rdist_to_dist(min_rdist_dual(bt1, i_node1,
                                               bt2, i_node2))

cdef inline DTYPE_t max_rdist_dual(BinaryTree bt1, ITYPE_t i_node1,
                                   BinaryTree bt2, ITYPE_t i_node2):
    cdef ITYPE_t n_features = bt1.data.shape[1]

    cdef DTYPE_t d, d1, d2, rdist=0.0
    cdef DTYPE_t zero = 0.0
    cdef ITYPE_t j

    for j in range(n_features):
        d1 = fabs(bt1.node_bounds[0, i_node1, j]
                  - bt2.node_bounds[1, i_node2, j])
        d2 = fabs(bt1.node_bounds[1, i_node1, j]
                  - bt2.node_bounds[0, i_node2, j])
        rdist += pow(fmax(d1, d2), bt1.dm.p)

    return rdist

cdef inline DTYPE_t max_dist_dual(BinaryTree bt1, ITYPE_t i_node1,
                                  BinaryTree bt2, ITYPE_t i_node2):
    return bt1.dm.rdist_to_dist(max_rdist_dual(bt1, i_node1,
                                               bt2, i_node2))
