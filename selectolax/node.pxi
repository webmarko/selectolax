from libc.stdlib cimport free


cdef class Node:
    """A class that represents HTML node (element)."""
    cdef myhtml_tree_node_t *node
    cdef HTMLParser parser

    cdef _init(self, myhtml_tree_node_t *node, HTMLParser parser):
        # custom init, because __cinit__ doesn't accept C types
        self.node = node
        # Keep reference to the selector object, so myhtml structures will not be garbage collected prematurely
        self.parser = parser

    @property
    def attributes(self):
        """Get all attributes that belong to the current node.

        Note that the value of empty attributes is None.

        Returns
        -------
        attributes : dictionary of all attributes.
        """
        cdef myhtml_tree_attr_t *attr = myhtml_node_attribute_first(self.node)
        attributes = dict()

        while attr:
            key = attr.key.data.decode('UTF-8', self.parser.decode_errors)
            if attr.value.data:
                value = attr.value.data.decode('UTF-8', self.parser.decode_errors)
            else:
                value = None
            attributes[key] = value

            attr = attr.next

        return attributes

    def text(self, deep=True, separator='', strip=False):
        """Returns the text of the node including the text of all child nodes.

        Parameters
        ----------
        strip : bool, default False
        separator : str, default ''
        deep : bool, default True
            Whenever to include the text from all child nodes.

        Returns
        -------
        text : str

        """
        text = ""
        cdef const char* c_text
        cdef myhtml_tree_node_t*node = self.node.child

        if not deep:
            texts = []
            while node != NULL:
                if node.tag_id == MyHTML_TAG__TEXT:
                    c_text = myhtml_node_text(node, NULL)
                    if c_text != NULL:
                        node_text = c_text.decode('utf-8', self.parser.decode_errors)
                        text = append_text(text, node_text, separator, strip)
                node = node.next
        else:
            return self._text_deep(node, separator=separator, strip=strip)
        return text

    cdef _text_deep(self, myhtml_tree_node_t *node, separator='', strip=False):
        text = ""

        # Depth-first left-to-right tree traversal
        if node != NULL:
            if node.tag_id == MyHTML_TAG__TEXT:
                c_text = myhtml_node_text(node, NULL)
                if c_text != NULL:
                    node_text = c_text.decode('utf-8', self.parser.decode_errors)
                    text = append_text(text, node_text, separator, strip)

            if node.child is not NULL:
                text += self._text_deep(node.child, separator=separator, strip=strip)
            if node.next is not NULL:
                text += self._text_deep(node.next, separator=separator, strip=strip)

        return text

    def iter(self):
        """Iterate over nodes on the current level

        Returns
        -------
        generator
        """

        cdef myhtml_tree_node_t*node = self.node.child
        cdef Node next_node
        while node != NULL:
            if node.tag_id != MyHTML_TAG__TEXT:
                next_node = Node()
                next_node._init(node, self.parser)
                yield next_node

            node = node.next

    @property
    def tag(self):
        """Return the name of the current tag (e.g. div, p, img).

        Returns
        -------
        text : str
        """
        cdef const char *c_text
        c_text = myhtml_tag_name_by_id(self.node.tree, self.node.tag_id, NULL)
        text = None
        if c_text:
            text = c_text.decode("utf-8", self.parser.decode_errors)
        return text

    @property
    def child(self):
        """Return the child of current node."""
        cdef Node node
        if self.node.child:
            node = Node()
            node._init(self.node.child, self.parser)
            return node
        return None

    @property
    def parent(self):
        """Return the parent of current node."""
        cdef Node node
        if self.node.parent:
            node = Node()
            node._init(self.node.parent, self.parser)
            return node
        return None

    @property
    def next(self):
        """Return next node."""
        cdef Node node
        if self.node.next:
            node = Node()
            node._init(self.node.next, self.parser)
            return node
        return None

    @property
    def prev(self):
        """Return previous node."""
        cdef Node node
        if self.node.prev:
            node = Node()
            node._init(self.node.prev, self.parser)
            return node
        return None

    @property
    def last_child(self):
        """Return last child node."""
        cdef Node node
        if self.node.last_child:
            node = Node()
            node._init(self.node.last_child, self.parser)
            return node
        return None

    @property
    def html(self):
        """Return html representation of current node including all its child nodes.

        Returns
        -------
        text : str
        """
        cdef mycore_string_raw_t c_str
        c_str.data = NULL
        c_str.length = 0
        c_str.size = 0

        cdef mystatus_t status
        status = myhtml_serialization(self.node, &c_str)

        if status == 0 and c_str.data:
            html = c_str.data.decode('utf-8')
            free(c_str.data)
            return html

        return None

    def css(self, str query):
        """Performs CSS selector against current node and its child nodes."""
        cdef myhtml_collection_t *collection
        cdef Selector selector = Selector(query)

        result = list()
        collection = selector.find(self.node)

        if collection != NULL:
            for i in range(collection.length):
                node = Node()
                node._init(collection.list[i], self.parser)
                result.append(node)

            myhtml_collection_destroy(collection)

        return result

    def css_first(self, str query, default=None, strict=False):
        """Performs CSS selector against current node and its child nodes."""
        results = self.css(query)
        n_results = len(results)

        if n_results > 0:

            if strict and n_results > 1:
                raise ValueError("Expected 1 match, but found %s matches" % n_results)

            return results[0]

        return default

    def decompose(self, recursive=True):
        """Remove an element from the tree.

        Parameters
        ----------
        recursive : bool, default True
            Whenever to delete all its child nodes
        """
        if recursive:
            myhtml_node_delete_recursive(self.node)
        else:
            myhtml_node_delete(self.node)

    def __repr__(self):
        return '<Node %s>' % self.tag

cdef inline str append_text(str text, str node_text, str separator='', bint strip=False):

        if strip:
            text += node_text.strip() + separator
        else:
            text += node_text + separator

        return text
