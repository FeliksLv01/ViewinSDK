# Inspection is explicit opt-in; keep its entry points when included in internal Release builds.
-keep class app.viewin.sdk.Viewin { public *; }

# Optional RecyclerView public-API bridge. These rules do not add a RecyclerView dependency.
-keepnames class androidx.recyclerview.widget.RecyclerView
-keepnames class androidx.recyclerview.widget.RecyclerView$Adapter
-keepnames class androidx.recyclerview.widget.RecyclerView$ViewHolder
-keepnames class androidx.recyclerview.widget.LinearLayoutManager
-keepnames class androidx.recyclerview.widget.GridLayoutManager
-keepnames class androidx.recyclerview.widget.StaggeredGridLayoutManager
-keepclassmembers,allowoptimization class androidx.recyclerview.widget.RecyclerView {
    public *** getAdapter();
    public *** getLayoutManager();
    public *** findContainingViewHolder(android.view.View);
    public int getScrollState();
    public boolean isComputingLayout();
    public boolean hasPendingAdapterUpdates();
    public boolean isLayoutSuppressed();
}
-keepclassmembers,allowoptimization class androidx.recyclerview.widget.RecyclerView$Adapter {
    public int getItemCount();
    public boolean hasStableIds();
}
-keepclassmembers,allowoptimization class androidx.recyclerview.widget.RecyclerView$ViewHolder {
    public *** getBindingAdapter();
    public int getAbsoluteAdapterPosition();
    public int getBindingAdapterPosition();
    public int getLayoutPosition();
    public int getItemViewType();
    public long getItemId();
    public boolean isRecyclable();
}
-keepclassmembers,allowoptimization class androidx.recyclerview.widget.LinearLayoutManager {
    public int getOrientation();
    public boolean getReverseLayout();
    public boolean getStackFromEnd();
    public int findFirstVisibleItemPosition();
    public int findLastVisibleItemPosition();
}
-keepclassmembers,allowoptimization class androidx.recyclerview.widget.GridLayoutManager { public int getSpanCount(); }
-keepclassmembers,allowoptimization class androidx.recyclerview.widget.StaggeredGridLayoutManager {
    public int getOrientation();
    public boolean getReverseLayout();
    public int getSpanCount();
}
